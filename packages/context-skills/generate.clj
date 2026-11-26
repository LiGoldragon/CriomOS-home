;; Projects every belief module of the pinned cohort into the skill
;; directory each harness reads: <out>/<surface>/skills/<module>/SKILL.md.
;; Arguments: out, then one "<root>=<revision>" per context repository.
(require '[babashka.process :as process]
         '[clojure.java.io :as io]
         '[clojure.string :as str])
(import '[java.nio.file Files])

(def module-types
  ["vision" "intent" "spirit" "knowledge" "compensation" "role" "raw" "inquiry"])

;; Every surface a harness reads, the harness its text is rendered for,
;; and whether it carries Codex's invocation policy file.
(def surfaces
  [{:directory ".claude/skills" :harness :claude}
   {:directory ".agents/skills" :harness :codex :codex-policy true}
   {:directory ".codex/skills" :harness :codex :codex-policy true}
   {:directory ".pi/skills" :harness :pi}
   {:directory ".opencode/skills" :harness :opencode}])

(defn fail [& parts]
  (binding [*out* *err*] (println (apply str parts)))
  (System/exit 1))

(defn header [body]
  (when (str/starts-with? body "---\n")
    (first (str/split (subs body 4) #"\n---\n" 2))))

(defn user-only? [body]
  (boolean (some #(= "user-only: true" (str/trim %))
                 (some-> (header body) str/split-lines))))

(defn render-body
  "Keeps the lines selected for one harness; directive lines are dropped."
  [harness body]
  (loop [lines (re-seq #"[^\n]*\n|[^\n]+$" body)
         conditions []
         raw false
         out (StringBuilder.)]
    (if-let [line (first lines)]
      (let [directive (str/trim line)
            shown (every? first conditions)]
        (cond
          raw (if (= directive "{% endraw %}")
                (recur (rest lines) conditions false out)
                (recur (rest lines) conditions true (cond-> out shown (.append line))))
          (= directive "{% raw %}") (recur (rest lines) conditions true out)
          (= directive "{% endraw %}") (recur (rest lines) conditions false out)
          (#{"{% if claude %}" "{% if codex %}" "{% if pi %}" "{% if opencode %}"} directive)
          (recur (rest lines)
                 (conj conditions [(= (keyword (second (re-find #"if (\w+)" directive))) harness) false])
                 false out)
          (= directive "{% else %}")
          (recur (rest lines)
                 (if-let [[selected seen] (peek conditions)]
                   (if seen conditions (conj (pop conditions) [(not selected) true]))
                   conditions)
                 false out)
          (= directive "{% endif %}") (recur (rest lines) (if (seq conditions) (pop conditions) conditions) false out)
          :else (recur (rest lines) conditions false (cond-> out shown (.append line)))))
      (str out))))

(defn render [{:keys [harness]} {:keys [name body]}]
  (let [rendered (render-body harness body)]
    (cond
      (= harness :opencode)
      (if (str/starts-with? rendered "---\n")
        (str "---\nname: " name "\n" (subs rendered 4))
        (str "---\nname: " name "\n---\n" rendered))
      (and (= harness :claude) (user-only? body))
      (str/replace rendered "user-only: true" "disable-model-invocation: true")
      :else rendered)))

(defn symbolic-link? [file]
  (Files/isSymbolicLink (.toPath file)))

;; Temporary filesystem adapter. Curriculum's client module listing will
;; replace this traversal and supply identity, description and file together.
(defn flat-role-module [file revision]
  (let [file-name (.getName file)]
    (when-not (and (.isFile file) (not (symbolic-link? file)) (str/ends-with? file-name ".md"))
      (fail "not a module topic directory: " file))
    (let [subject (str/replace file-name #"\.md$" "")]
      (when-not (re-matches #"[a-z0-9-]+" subject) (fail "invalid role subject: " file))
      {:name (str "role:" subject)
       :body (slurp file)
       :source (str "role/" file-name)
       :revision revision})))

(defn valid-version?
  "A version is a plain integer, a span `<first>-<last>` with first < last, or `all`."
  [version]
  (let [integer #"(?:0|[1-9][0-9]*)"]
    (or (boolean (re-matches integer version))
        (= version "all")
        (when-let [[_ first-version last-version] (re-matches #"([^-]+)-([^-]+)" version)]
          (and (re-matches integer first-version)
               (re-matches integer last-version)
               (< (bigint first-version) (bigint last-version)))))))

(defn singleton-modules [kind topic-dir revision]
  (let [topic (.getName topic-dir)]
    (when-not (and (.isDirectory topic-dir) (not (symbolic-link? topic-dir)))
      (fail "not a module topic directory: " topic-dir))
    (when-not (re-matches #"[a-z0-9-]+" topic)
      (fail "invalid topic: " topic-dir))
    (for [file (sort-by #(.getName %) (.listFiles topic-dir))
          :let [file-name (.getName file)]]
      (do
        (when-not (and (.isFile file) (not (symbolic-link? file)) (str/ends-with? file-name ".md"))
          (fail "not a module source: " file))
        (let [version (str/replace file-name #"\.md$" "")]
          (when-not (valid-version? version) (fail "invalid version: " file))
          {:name (str kind ":" topic ":" version)
           :body (slurp file)
           :source (str kind "/" topic "/" file-name)
           :revision revision})))))

(defn modules [root revision]
  (mapcat
    (fn [kind]
      (let [kind-dir (io/file root kind)]
        (if-not (.exists kind-dir)
          []
          (do
            (when-not (and (.isDirectory kind-dir) (not (symbolic-link? kind-dir)))
              (fail "not a module kind directory: " kind-dir))
            (mapcat
              (fn [entry]
                (if (and (= kind "role") (.isFile entry))
                  [(flat-role-module entry revision)]
                  (singleton-modules kind entry revision)))
              (sort-by #(.getName %) (.listFiles kind-dir)))))))
    module-types))

(defn exportable-modules [modules]
  (let [classifier (System/getenv "CURRICULUM_SKILL_INVENTORY")
        separator (str (char 0))]
    (when (str/blank? classifier) (fail "missing Curriculum skill inventory program"))
    (when (some #(str/includes? (:body %) separator) modules)
      (fail "unsupported NUL in skill source"))
    (let [input (apply str (map #(str (:body %) separator) modules))
          result @(process/process [classifier] {:in input :out :string :err :string})
          classifications (if (empty? (:out result)) [] (str/split-lines (:out result)))]
      (when (or (not (zero? (:exit result)))
                (not= (count classifications) (count modules))
                (not-every? #{"Public" "Specialist"} classifications))
        (fail "Curriculum skill inventory refused: " (:err result)))
      (keep (fn [[classification module]] (when (= "Public" classification) module))
            (map vector classifications modules)))))

(let [[out & sources] *command-line-args*
      all (mapcat #(apply modules (str/split % #"=" 2)) sources)
      duplicates (->> all (map :name) frequencies (filter #(> (val %) 1)) keys)]
  (when (empty? sources) (fail "no context repository given"))
  (when (seq duplicates) (fail "duplicate module ids: " (str/join " " duplicates)))
  (let [modules (exportable-modules all)]
    ;; Even an empty public inventory is a complete projection: regeneration
    ;; must be able to remove earlier copies from every target.
    (doseq [surface surfaces]
      (.mkdirs (io/file out (:directory surface))))
    (doseq [surface surfaces
            module modules
            :let [dir (io/file out (:directory surface) (:name module))]]
      (.mkdirs dir)
      (spit (io/file dir "SKILL.md") (render surface module))
      (when (and (:codex-policy surface) (user-only? (:body module)))
        (.mkdirs (io/file dir "agents"))
        (spit (io/file dir "agents" "openai.yaml") "policy:\n  allow_implicit_invocation: false\n")))
    ;; One line per published module: id, repository revision, source path.
    (spit (io/file out "modules")
          (str/join (for [{:keys [name revision source]} (sort-by :name modules)]
                      (str name " " revision " " source "\n"))))))

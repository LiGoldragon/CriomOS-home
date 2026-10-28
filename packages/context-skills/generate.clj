;; Projects every belief module of the pinned cohort into the skill
;; directory each harness reads: <out>/<surface>/skills/<module>/SKILL.md.
;; Arguments: out, then one "<root>=<revision>" per context repository.
(require '[clojure.java.io :as io]
         '[clojure.string :as str])

(def module-types
  ["vision" "intent" "spirit" "knowledge" "compensation" "role" "raw"])

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

(defn modules [root revision]
  (for [kind module-types
        :let [dir (io/file root kind)]
        :when (.isDirectory dir)
        file (sort-by #(.getName %) (.listFiles dir))
        :let [file-name (.getName file)]]
    (do
      (when-not (and (.isFile file) (str/ends-with? file-name ".md"))
        (fail "not a module source: " file))
      (let [subject (str/replace file-name #"\.md$" "")]
        (when-not (re-matches #"[a-z0-9-]+" subject) (fail "invalid subject: " file))
        {:name (str kind "-" subject)
         :body (slurp file)
         :source (str kind "/" file-name)
         :revision revision}))))

(let [[out & sources] *command-line-args*
      all (mapcat #(apply modules (str/split % #"=" 2)) sources)
      duplicates (->> all (map :name) frequencies (filter #(> (val %) 1)) keys)]
  (when (empty? sources) (fail "no context repository given"))
  (when (seq duplicates) (fail "duplicate module ids: " (str/join " " duplicates)))
  (doseq [surface surfaces
          module all
          :let [dir (io/file out (:directory surface) (:name module))]]
    (.mkdirs dir)
    (spit (io/file dir "SKILL.md") (render surface module))
    (when (and (:codex-policy surface) (user-only? (:body module)))
      (.mkdirs (io/file dir "agents"))
      (spit (io/file dir "agents" "openai.yaml") "policy:\n  allow_implicit_invocation: false\n")))
  ;; One line per module: id, repository revision, source path.
  (spit (io/file out "modules")
        (str/join (for [{:keys [name revision source]} (sort-by :name all)]
                    (str name " " revision " " source "\n")))))

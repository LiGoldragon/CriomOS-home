;; Configure.Metaflows from config/main-flow: every declared metaflow, and
;; each extra Address named on the command line, with the context modules a
;; launch of it composes: its aspect's defaults, then the row's own additions
;; (system :modules, user :user-modules).
(require '[clojure.edn :as edn]
         '[clojure.java.io :as io]
         '[clojure.string :as str])
(let [[root & extra] *command-line-args*
      read-data #(edn/read-string (slurp %))
      aspects (into {} (for [aspect [:Psyche :Mind :Field]]
                        [aspect (read-data (io/file root (str (str/lower-case (name aspect)) ".edn")))]))
      rows (map read-data (filter #(.endsWith (.getName %) ".edn")
                                  (sort-by #(.getName %) (.listFiles (io/file root "metaflow")))))
      module-name #(if (map? %) (name (:name %)) (name %))
      defaults (fn [aspect placement]
                 (let [modules (get-in aspects [aspect :modules placement])]
                   (when-not (seq modules)
                     (throw (ex-info "MissingAspectModules" {:aspect aspect :placement placement})))
                   (map module-name modules)))
      declared (fn [aspect topic layer system user]
                 {:address [(name aspect) (str/lower-case (name topic)) (name layer)]
                  :system (distinct (concat (defaults aspect :system) (map module-name system)))
                  :user (distinct (concat (defaults aspect :user) (map module-name user)))})
      entries (concat
                (for [row rows]
                  (declared (:aspect row) (:topic row) (:layer row) (:modules row) (:user-modules row)))
                (for [address extra
                      :let [[aspect topic layer] (str/split address #"\s+")]]
                  (declared (keyword aspect) topic (keyword layer) [] [])))
      addresses (map :address entries)]
  (when-not (= (count addresses) (count (distinct addresses)))
    (throw (ex-info "DuplicateMetaflowDeclaration" {:addresses addresses})))
  (println (str "Configure.Metaflows.[ "
                (str/join " " (for [{:keys [address system user]} entries]
                                (str "{ { " (str/join " " address) " } [ " (str/join " " system)
                                     " ] [ " (str/join " " user) " ] }")))
                " ]")))

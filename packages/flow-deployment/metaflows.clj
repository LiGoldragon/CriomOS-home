(require '[clojure.edn :as edn]
         '[clojure.java.io :as io]
         '[clojure.string :as str])
;; Prints one Configure.Metaflows datom: each declared metaflow's Address with
;; its system and user modules, the aspect's standing modules first and the
;; metaflow's own after them, each named once.
(let [root (first *command-line-args*)
      read-data #(edn/read-string (slurp %))
      aspects (into {} (for [aspect [:Psyche :Mind :Field]]
                         [aspect (read-data (io/file root (str (str/lower-case (name aspect)) ".edn")))]))
      rows (map read-data (filter #(.endsWith (.getName %) ".edn")
                                  (sort-by #(.getName %) (.listFiles (io/file root "metaflow")))))
      module-name #(name (if (map? %) (:name %) %))
      composed (fn [aspect placement own]
                 (let [standing (get-in aspects [aspect :modules placement])]
                   (when-not (vector? standing)
                     (throw (ex-info "MissingStandingModules" {:aspect aspect :placement placement})))
                   (vec (distinct (map module-name (concat standing own))))))
      entries (mapv (fn [row]
                      (let [aspect (:aspect row)
                            address [(name aspect)
                                     (str/lower-case (name (:topic row)))
                                     (name (:layer row))]]
                        {:address address
                         :datom (str "{ { " (str/join " " address) " } [ "
                                     (str/join " " (composed aspect :system (:modules row)))
                                     " ] [ "
                                     (str/join " " (composed aspect :user (:user-modules row)))
                                     " ] }")}))
                    rows)
      addresses (mapv :address entries)]
  (when-not (= (count addresses) (count (distinct addresses)))
    (throw (ex-info "DuplicateMetaflowAddress" {})))
  (println (str "Configure.Metaflows.[ " (str/join " " (map :datom entries)) " ]")))

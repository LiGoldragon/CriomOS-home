(require '[clojure.edn :as edn]
         '[clojure.java.io :as io]
         '[clojure.string :as str])
(let [root (first *command-line-args*)
      read-data #(edn/read-string (slurp %))
      shared (read-data (io/file root "shared.edn"))
      aspects (into {} (for [aspect [:Psyche :Mind :Field]]
                        [aspect (read-data (io/file root (str (str/lower-case (name aspect)) ".edn")))]))
      rows (map read-data (filter #(.endsWith (.getName %) ".edn")
                                  (sort-by #(.getName %) (.listFiles (io/file root "metaflow")))))]
  (doseq [row rows]
    (let [harness (or (get-in row [:voice :harness]) (get-in aspects [(:aspect row) :harness]))
          values (get-in shared [:leave-outs harness])]
      (when-not (and (vector? values) (seq values) (= (count values) (count (distinct values))))
        (throw (ex-info "MissingOrInvalidLeaveOutDefaults" {:harness harness})))
      (println (str "Configure.LeaveOut.{ { " (name (:aspect row)) " "
                    (str/lower-case (name (:topic row))) " " (name (:layer row))
                    " } [ " (str/join " " (map name values)) " ] }")))))

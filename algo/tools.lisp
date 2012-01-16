;;; Thu 29 Dec, 2011 (c) Marc Kuo
;;; Tools to be shared among algorithms
;;; ---------------------------
(in-package :open-vrp.algo)

;; Thu Dec 8, 2011
;; challenge: what if the vehicle is located on the node n - use only for initial insertion?
(defgeneric get-closest-vehicle (node problem)
  (:method (node problem) "get-closest-vehicle: Expects <node> and <problem> inputs!")
  (:documentation "Returns the closest <vehicle> to <node>. Used by insertion heuristic. When multiple <vehicle> are on equal distance, choose first one (i.e. lowest ID)."))
 
(defmethod get-closest-vehicle ((n node) (prob problem))
  (let ((distances (mapcar #'(lambda (x) (node-distance (last-node x) n))
			   (fleet-vehicles (problem-fleet prob))))) ;all distances
    (vehicle prob (get-min-index distances))))

;; allow only feasible vehicles to be selected
(defmethod get-closest-vehicle ((n node) (prob CVRP))
  (let* ((vehicles (fleet-vehicles (problem-fleet prob)))
	 (dists (mapcar #'(lambda (x) (node-distance (last-node x) n)) vehicles))
	 (caps (mapcar #'(lambda (x)
			   (multiple-value-bind (c cap)
			       (in-capacityp x) (when c cap)))
		       vehicles))
	 (filtered (mapcar #'(lambda (dist cap)
			       (if (> (node-demand n) cap) nil dist))
			   dists caps)))
    (vehicle prob (get-min-index filtered))))	   

(defmethod get-closest-vehicle ((n node) (prob VRPTW))
  (let* ((vehicles (fleet-vehicles (problem-fleet prob)))
	 (dists (mapcar #'(lambda (x) (node-distance (last-node x) n)) vehicles))
	 (times (mapcar #'(lambda (x)
			    (multiple-value-bind (c time)
				(in-timep x (problem-network prob)) (when c time)))
			vehicles))
	 (filtered (mapcar #'(lambda (veh dist time)
			       (if (> (+ time (travel-time veh
							   (problem-network prob)
							   (node-id (last-node veh))
							   (node-id n)))
				      (node-end n))
				   nil
				   dist))
			   vehicles dists times)))
    (vehicle prob (get-min-index filtered))))	   

;; Mon Dec 12, 2011 - TODO
;; Attempt for Iterator on <Algo> object. Used by TS (or even GA or other metaheuristics).
;; --------------------------------------------

;; initializer
;; -----------
(defgeneric initialize (problem algo)
  (:method (problem algo)
    "initialize: Requires <Problem> and <Algo> as inputs.")
  (:documentation "Initializes the initial solution for the algo object. For Tabu Search, the default heuristic for generating an initial solution is 'greedy-insertion, which is read from the slot :init-heur."))

;; iterator
;; ------------
(defgeneric iterate (algo)
  (:method (algo)
    "iterate: This algo is not defined.")
  (:documentation "Runs the algo one iteration. Uses the algo's slot current-sol as current solution on which the algo runs one iteration. When algo's slot iterations is 0, then print the best solution found by this algo object. Returns the <algo> object when finished, otherwise returns <problem> solution object."))

(defmethod iterate :around ((a algo))
  (if (< (algo-iterations a) 1)
      (progn
	(print-routes (algo-best-sol a))
	a)
      (call-next-method))) ; otherwise iterate

(defmethod iterate :after ((a algo))
  (setf (algo-iterations a) (1- (algo-iterations a)))
  (let* ((sol (algo-current-sol a))
	 (new-fitness (fitness sol))
	 (best-fitness (algo-best-fitness a)))
    (print-routes sol)
    (when (or (null best-fitness)
	      (< new-fitness best-fitness))
      (setf (algo-best-fitness a) new-fitness)
      (setf (algo-best-sol a) (copy-object sol)))))

;; Resume run - add some more iterations
;; ------------------------
(defgeneric iterate-more (algo int)
  (:method (algo int) "iterate-more: expects <Algo> and int as inputs")
  (:documentation "When an algo finished (i.e. iterations = 0) using iterate-more allows you to keep running it x more iterations."))

(defmethod iterate-more ((a algo) int)
  (setf (algo-iterations a) int)
  (run-algo (algo-current-sol a) a))

;; Tabu Search animate
;; -------------------------
(defmethod iterate :after ((ts tabu-search))
  (when (tabu-search-animate ts)
    (plot-solution (algo-current-sol ts) (with-output-to-string (s)
					   (princ "run-frames/Iteration " s)
					   (princ (algo-iterations ts) s)
					   (princ ".png" s)))))
;; --------------------------


;; Generate-moves
;; -------------------
(defgeneric generate-moves (algo)
  (:method (algo)
    "generate-moves: This algo is not defined; cannot generate moves.")
  (:documentation "Given the algo object, that contains the current solution, generate potential <moves> for next iteration as defined by the algo. e.g. insertion moves for TS and chromosome pool for GA."))

;; Perform move
;; ---------------------
(defgeneric perform-move (sol move)
  (:method (sol move)
    "perform-move: This move is not defined.")
  (:documentation "Performs the move defined in <move> on the solution. Returns the new solution (which is a class of <Problem>)"))

;; logging
(defmethod perform-move :after ((prob problem) (mv move))
  (print "Performing ")
  (princ (type-of mv))
  (princ " with Node ")
  (princ (move-node-ID mv))
  (princ " and Vehicle ")
  (princ (move-vehicle-ID mv))
  (when (eq (type-of mv) 'insertion-move)
    (princ " and Index ")
    (princ (move-index mv))))

;; Assess move(s)
;; ------------------------
(defgeneric assess-move (sol move)
  (:method (sol move)
    "assess-move: This move is not defined.")
  (:documentation "The <Move> is assessed by calculating the fitness of solution before, and after. The fitness is the difference and is stored in the :fitness slot of the <Move> object."))

(defun fitness-before-after (sol operation)
  "Given <Problem> object and an #'operation function that takes the <problem> as input, return the difference of fitness between after and before."
  (let* ((before (fitness sol))
	 (clone (copy-object sol)))
    (funcall operation clone)
    (- (fitness clone) before)))
    
(defmethod assess-move ((sol problem) (m move))
  "Assesses the effect on fitness when <move> is performed on <problem> (on a clone - undestructive)."
  (setf (move-fitness m)
	(fitness-before-after sol #'(lambda (x) (perform-move x m)))))

(defun assess-moves (solution moves)
  "Given a list of <Move> objects, assess them all on the solution (uses assess-move), and setf the move's :fitness slots. Returns the list of moves."
  (mapcar #'(lambda (move) (assess-move solution move)) moves)
  moves)

;; Select move
;; -------------------
(defgeneric select-move (algo moves)
  (:method (algo moves) "select-move: not defined for <Algo>")
  (:documentation "Given an <Algo> object and the list of <Moves>, select a move. By default, sort the moves and select the best one, but e.g. for tabu-search, check first of the <Move> is tabu."))

(defun sort-moves (moves)
  "Given a list of <Move>s, sort them according to fitness (ascending). Undestructive."
  (sort-ignore-nil moves #'< :key #'move-fitness))

(defmethod select-move ((a algo) moves)
  (car (sort-moves moves)))

;; ------------------------------------------------
#!/usr/bin/env gsi

(declare (standard-bindings))

(define allocate-registers? #t) ; can be turned off to reduce compilation time
(define fold-constants?     #t)
(define coalesce?           #t)

;; to use when interpreting
'(begin (include "asm.scm")
       (include "pic18.scm")
       (include "pic18-sim.scm")
       (include "utilities.scm")
       (include "ast.scm")
       (include "operators.scm")
       (include "cte.scm")
       (include "parser.scm")
       (include "cfg.scm")
       (include "optimizations.scm")
       (include "code-generation.scm")
       (include "register-allocation.scm")
       (include "profiler.scm"))
;; to use with compiled code
(begin (load "asm")
       (load "pic18")
       (load "pic18-sim")
       (load "utilities")
       (load "ast")
       (load "operators")
       (load "cte")
       (load "parser")
       (load "cfg")
       (load "optimizations")
       (load "code-generation")
       (load "register-allocation")
       (load "profiler"))

;------------------------------------------------------------------------------

;; temporary solution, to support more than int
(set! ##six-types ;; TODO signed types ?
  '((int     . #f)
    (byte    . #f)
    (uint8   . #f)
    (uint16  . #f)
    (uint32  . #f)
    (char    . #f)
    (bool    . #f)
    (void    . #f)
    (float   . #f)
    (double  . #f)
    (obj     . #f)))
;; TODO typedef should add to this list

'(current-exception-handler (lambda (exc) (##repl))) ; when not running in the repl

(define preprocess? #t)
(define (read-source filename)
  (if preprocess?
      (shell-command (string-append "cpp -P " filename " > " filename ".tmp")))
;;   (##read-all-as-a-begin-expr-from-path ;; TODO use vectorized notation to have info on errors (where in the source)
;;    (string-append filename ".tmp")
;;    (readtable-start-syntax-set (current-readtable) 'six)
;;    ##wrap-datum
;;    ##unwrap-datum)
  (with-input-from-file
      (string-append filename ".tmp")
    (lambda ()
      (input-port-readtable-set!
       (current-input-port)
       (readtable-start-syntax-set
        (input-port-readtable (current-input-port))
        'six))
      (read-all)))
  )


(define asm-filename #f)

(define (main filename . data)

  (output-port-readtable-set!
   (current-output-port)
   (readtable-sharing-allowed?-set
    (output-port-readtable (current-output-port))
    #t))

  (let ((source (read-source filename)))
    '(pretty-print source)
    (let* ((ast (parse source)))
      '(pretty-print ast)
      (let ((cfg (generate-cfg ast)))
	'(print-cfg-bbs cfg)
	'(pretty-print cfg)
        (remove-branch-cascades-and-dead-code cfg)
	(remove-converging-branches cfg) ;; TODO maybe make it possible to disable it, the one before, and the next one ?
	(remove-instructions-after-branchs cfg)
	'(print-cfg-bbs cfg)
 	(if allocate-registers? (allocate-registers cfg))
	(assembler-gen filename cfg)
	(asm-assemble)
	'(asm-display-listing (current-output-port))
	(set! asm-filename (string-append filename ".s"))
	(with-output-to-file asm-filename
	  (lambda () (asm-display-listing (current-output-port))))
	(with-output-to-file (string-append filename ".reg")
	  (lambda ()
	    (display "(")
	    (for-each (lambda (x)
			;; write it in hex, for easier cross-reference with the
			;; simulation
			(write (cons (number->string (car x) 16) (cdr x)))
			(display "\n"))
		    (table->list register-table))
	  (display ")")))
	(asm-write-hex-file (string-append filename ".hex"))
	(asm-end!)
	;; data contains a list of additional hex files
	(apply execute-hex-files (cons (string-append filename ".hex") data))
	#t))))

(define (picobit prog #!optional (recompile? #f))
  (set! trace-instr #f)
  (if recompile?
      (main "tests/picobit/picobit-vm-sixpic.c" prog)
      (simulate (list "tests/picobit/picobit-vm-sixpic.c.hex" prog)
		"tests/picobit/picobit-vm-sixpic.c.map"
		"tests/picobit/picobit-vm-sixpic.c.reg"
		"tests/picobit/picobit-vm-sixpic.c.s")))

(define (picobit-orig prog #!optional (recompile? #f))
  (set! trace-instr #f)
  ;; no need to preprocess, I have a custom script that patches it for SIXPIC
  (set! preprocess? #f)
  (if recompile?
      (begin (load "orig/typedefs.tmp.scm")
	     (main "orig/picobit-vm.c" prog))
      (simulate (list "orig/picobit-vm.c.hex" prog)
		"orig/picobit-vm.c.map"
		"orig/picobit-vm.c.reg"
		"orig/picobit-vm.c.s")))

(define (simulate hexs map-file reg-file asm-file)
  (let ((regs (with-input-from-file reg-file read)))
    (set! register-table
	  (list->table
	   (map (lambda (x) (cons (string->number (car x) 16) (cdr x)))
		regs)))
    (set! reverse-register-table (make-table))
    (for-each (lambda (x)
		(for-each (lambda (y)
			    (table-set! reverse-register-table
					(cadr y)
					(string->number (car x) 16)))
			  (cdr x)))
	      regs))
  (set! asm-filename asm-file)
  (apply execute-hex-files hexs))

;; (include "../statprof/statprof.scm")
;; (define (profile) ; profile using picobit
;;   (time (begin (with-exception-catcher
;; 		;; to have the profiling results even it the compilation fails
;; 		(lambda (x)
;; 		  (profile-stop!)
;; 		  (write-profile-report "profiling-picobit"))
;; 		(lambda ()
;; 		  (profile-start!)
;; 		  (main "tests/picobit/picobit-vm-sixpic.c")
;; 		  (profile-stop!)
;; 		  (write-profile-report "profiling-picobit")))
;; 	       (pp TOTAL:))))

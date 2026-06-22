//
//
//
//
//
//                             REDUNTANT FOR NOW 
//               WE WANT THE THE RULES TO BE A LARGE EXPRESSIONS GENERATOR , NOT A SIMPLIFIER . 
//          JOB OF GETTING THE OPTIMIZED ALTERNATIVES IS DONE BY NUMERICAL METHODS INSTEAD OF REWRITE RULES .
//
//


// // my_rules.rs


// use crate::{ConstantFold, MathLang};
// use egg::{rewrite, Rewrite};

// pub fn my_rules() -> Vec<Rewrite<MathLang, ConstantFold>> {
//     vec![
//         rewrite!("flip--";
//             "(- (sqrt ?a) (sqrt ?b))" =>
//             "(/ (- ?a ?b) (+ (sqrt ?a) (sqrt ?b)))"),

//         rewrite!("associate--l+b"; "(- (+ ?a ?b) ?c)" => "(+ ?b (- ?a ?c))"),
//         rewrite!("associate--r+"; "(- ?a (+ ?b ?c))" => "(- (- ?a ?b) ?c)"),

//         rewrite!("cancel-+-";  "(- (+ ?a ?b) ?a)" => "?b"),
//         rewrite!("cancel-+-2"; "(- (+ ?a ?b) ?b)" => "?a"),

//         rewrite!("cancel--+";  "(- ?a (+ ?a ?b))" => "(neg ?b)"),
//         rewrite!("cancel--+2"; "(- ?a (+ ?b ?a))" => "(neg ?b)"),

//         rewrite!("+-inverses";     "(- ?a ?a)" => "0"),
//         rewrite!("+-rgt-identity"; "(+ ?a 0)"  => "?a"),
//         rewrite!("+-lft-identity"; "(+ 0 ?a)"  => "?a"),
//     ]
// }

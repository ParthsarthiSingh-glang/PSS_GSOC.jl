// herbie_rules.rs
// Direct ports from herbie/src/core/rules.rkt

use crate::{ConstantFold, MathLang};
use egg::{rewrite, Rewrite};

pub fn herbie_rules() -> Vec<Rewrite<MathLang, ConstantFold>> {
    vec![
        // herbie/src/core/rules.rkt [polynomials group]
        rewrite!("flip--";
            "(- (sqrt ?a) (sqrt ?b))" =>
            "(/ (- ?a ?b) (+ (sqrt ?a) (sqrt ?b)))"),

        // herbie/src/core/rules.rkt [arithmetic / commutativity group]
        rewrite!("+-commutative"; "(+ ?a ?b)" => "(+ ?b ?a)"),

        // herbie/src/core/rules.rkt [arithmetic / associativity group]
        rewrite!("associate--l+"; "(- (+ ?a ?b) ?c)" => "(+ ?a (- ?b ?c))"),
        rewrite!("associate--r+"; "(- ?a (+ ?b ?c))" => "(- (- ?a ?b) ?c)"),

        // herbie/src/core/rules.rkt [arithmetic / identity group]
        rewrite!("+-inverses";     "(- ?a ?a)" => "0"),
        rewrite!("+-rgt-identity"; "(+ ?a 0)"  => "?a"),
        rewrite!("+-lft-identity"; "(+ 0 ?a)"  => "?a"),
    ]
}

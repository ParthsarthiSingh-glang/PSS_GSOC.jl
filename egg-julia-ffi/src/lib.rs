#![recursion_limit = "256"]

use egg::*;
use ordered_float::NotNan;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

pub type Constant = NotNan<f64>;


// herbie/egg-herbie/src/math.rs
define_language! {
    pub enum MathLang {

        "+"     = Add([Id; 2]),
        "-"     = Sub([Id; 2]),
        "*"     = Mul([Id; 2]),
        "/"     = Div([Id; 2]),
        "^"     = Pow([Id; 2]),
        "neg"   = Neg(Id),
        "sqrt"  = Sqrt(Id),
        "fabs"  = Fabs(Id),
        "ceil"  = Ceil(Id),
        "floor" = Floor(Id),
        "round" = Round(Id),
        "log"   = Log(Id),
        "cbrt"  = Cbrt(Id),

        // leaves
        Num(Constant),
        Symbol(egg::Symbol),

        //  Other(egg::Symbol, Vec<Id>) 
        Other(egg::Symbol, Vec<Id>),
    }
}

pub struct EGraphWithRoot {
    pub egraph: EGraph<MathLang, ()>,
    pub root:   Id,
}

fn make_rules() -> Vec<Rewrite<MathLang, ()>> {
    vec![
        // Herbie source: herbie/src/core/rules.rkt
        rewrite!("flip--";
            "(- (sqrt ?a) (sqrt ?b))" =>
            "(/ (- ?a ?b) (+ (sqrt ?a) (sqrt ?b)))")
    ]
}

// build egraph
#[no_mangle]
pub extern "C" fn egraph_create(expr_ptr: *const c_char) -> *mut EGraphWithRoot {
    let expr_str = unsafe { CStr::from_ptr(expr_ptr) }.to_str().unwrap();
    let expr: RecExpr<MathLang> = expr_str.parse().unwrap();
    let mut egraph = EGraph::new(());
    let root = egraph.add_expr(&expr);
    Box::into_raw(Box::new(EGraphWithRoot { egraph, root }))
}

// apply rewrite rules
#[no_mangle]
pub extern "C" fn egraph_saturate(ptr: *mut EGraphWithRoot) {
    let eg = unsafe { &mut *ptr };
    let expr = eg.egraph.id_to_expr(eg.root);
    let runner = Runner::default()
        .with_egraph(eg.egraph.clone())
        .with_expr(&expr)
        .run(&make_rules());
    eg.root   = runner.roots[0];
    eg.egraph = runner.egraph;
}

// default AstSize() cost fnc
#[no_mangle]
pub extern "C" fn egraph_extract(ptr: *mut EGraphWithRoot) -> *mut c_char {
    let eg = unsafe { &*ptr };
    let (_, best) = Extractor::new(&eg.egraph, AstSize).find_best(eg.root);
    CString::new(best.to_string()).unwrap().into_raw()
}

// free the EGraphWithRoot heap allocation
#[no_mangle]
pub extern "C" fn egraph_destroy(ptr: *mut EGraphWithRoot) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)) };
    }
}

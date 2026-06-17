#![recursion_limit = "256"]

use egg::*;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

pub type Constant = num_rational::BigRational;

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
    pub egraph:      EGraph<MathLang, ()>,
    pub root:        Id,
    pub stop_reason: u8,  // 0=Saturated 1=IterationLimit 2=NodeLimit 3=TimeLimit 4=Other
}

fn make_rules() -> Vec<Rewrite<MathLang, ()>> {
    vec![
        // Herbie source: herbie/src/core/rules.rkt
        rewrite!("flip--";
            "(- (sqrt ?a) (sqrt ?b))" =>
            "(/ (- ?a ?b) (+ (sqrt ?a) (sqrt ?b)))"),

        // Identity
        rewrite!("+-inverses";
            "(- ?a ?a)" => "0"),

        // Identity
        rewrite!("+-rgt-identity";
            "(+ ?a 0)" => "?a"),
        rewrite!("+-lft-identity";
            "(+ 0 ?a)" => "?a"),

        // Associativity
        rewrite!("associate--l+";
            "(- (+ ?a ?b) ?c)" => "(+ ?a (- ?b ?c))"),
        rewrite!("associate--r+";
            "(- ?a (+ ?b ?c))" => "(- (- ?a ?b) ?c)")
    ]
}

// build egraph
#[no_mangle]
pub extern "C" fn egraph_create(expr_ptr: *const c_char) -> *mut EGraphWithRoot {
    let expr_str = unsafe { CStr::from_ptr(expr_ptr) }.to_str().unwrap();
    let expr: RecExpr<MathLang> = expr_str.parse().unwrap();
    let mut egraph = EGraph::new(());
    let root = egraph.add_expr(&expr);
    Box::into_raw(Box::new(EGraphWithRoot { egraph, root, stop_reason: 4 }))
}

fn stop_reason_to_u8(reason: &Option<StopReason>) -> u8 {
    match reason {
        Some(StopReason::Saturated)        => 0,
        Some(StopReason::IterationLimit(_))=> 1,
        Some(StopReason::NodeLimit(_))     => 2,
        Some(StopReason::TimeLimit(_))     => 3,
        _                                  => 4,
    }
}

// apply rewrite rules with default limits
#[no_mangle]
pub extern "C" fn egraph_saturate(ptr: *mut EGraphWithRoot) {
    let eg = unsafe { &mut *ptr };
    let expr = eg.egraph.id_to_expr(eg.root);
    let runner = Runner::default()
        .with_egraph(eg.egraph.clone())
        .with_expr(&expr)
        .run(&make_rules());
    eg.stop_reason = stop_reason_to_u8(&runner.stop_reason);
    eg.root        = runner.roots[0];
    eg.egraph      = runner.egraph;
}

// 0=Saturated 1=IterationLimit 2=NodeLimit 3=TimeLimit 4=Other
#[no_mangle]
pub extern "C" fn egraph_stop_reason(ptr: *mut EGraphWithRoot) -> u8 {
    let eg = unsafe { &*ptr };
    eg.stop_reason
}

// default AstSize() cost fnc
// returns a CString heap allocation — caller must free via egraph_free_string
#[no_mangle]
pub extern "C" fn egraph_extract(ptr: *mut EGraphWithRoot) -> *mut c_char {
    let eg = unsafe { &*ptr };
    let (_, best) = Extractor::new(&eg.egraph, AstSize).find_best(eg.root);
    CString::new(best.to_string()).unwrap().into_raw()
}

// free the CString returned by egraph_extract
// mirrors egraph_destroy but for the extracted string allocation
#[no_mangle]
pub extern "C" fn egraph_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(CString::from_raw(ptr)) };
    }
}

// free the EGraphWithRoot heap allocation
#[no_mangle]
pub extern "C" fn egraph_destroy(ptr: *mut EGraphWithRoot) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)) };
    }
}

// ==================== UTILITY FUNCTIONS ====================
// e-graph interactions — herbie/egg-herbie/src/lib.rs

// total number of e-classes in the e-graph
#[no_mangle]
pub extern "C" fn egraph_size(ptr: *mut EGraphWithRoot) -> u32 {
    let eg = unsafe { &*ptr };
    eg.egraph.number_of_classes() as u32
}

// number of equivalent e-nodes in the e-class with the given id
#[no_mangle]
pub extern "C" fn egraph_eclass_size(ptr: *mut EGraphWithRoot, id: u32) -> u32 {
    let eg = unsafe { &*ptr };
    eg.egraph[Id::from(id as usize)].nodes.len() as u32
}

// canonical id for a given id (union-find lookup)
#[no_mangle]
pub extern "C" fn egraph_find(ptr: *mut EGraphWithRoot, id: u32) -> u32 {
    let eg = unsafe { &*ptr };
    let canon_id = eg.egraph.find(Id::from(id as usize));
    usize::from(canon_id) as u32
}

// id of the root e-class
#[no_mangle]
pub extern "C" fn egraph_root_id(ptr: *mut EGraphWithRoot) -> u32 {
    let eg = unsafe { &*ptr };
    usize::from(eg.root) as u32
}

// total unique enodes across all eclasses (memo.len())
// distinct from egraph_size() which returns number_of_classes()
#[no_mangle]
pub extern "C" fn egraph_total_size(ptr: *mut EGraphWithRoot) -> u32 {
    let eg = unsafe { &*ptr };
    eg.egraph.total_size() as u32
}

// check if an s-expression string is present in the egraph after saturation
// returns the eclass id if found, u32::MAX if not found
#[no_mangle]
pub extern "C" fn egraph_contains(ptr: *mut EGraphWithRoot, expr_ptr: *const c_char) -> u32 {
    let eg = unsafe { &*ptr };
    let expr_str = unsafe { CStr::from_ptr(expr_ptr) }.to_str().unwrap();
    let expr: RecExpr<MathLang> = match expr_str.parse() {
        Ok(e)  => e,
        Err(_) => return u32::MAX,
    };
    match eg.egraph.lookup_expr(&expr) {
        Some(id) => usize::from(id) as u32,
        None     => u32::MAX,
    }
}

// pretty-printed version of egraph_extract — use width to control line breaks
// free via egraph_free_string
#[no_mangle]
pub extern "C" fn egraph_pretty_extract(ptr: *mut EGraphWithRoot, width: u32) -> *mut c_char {
    let eg = unsafe { &*ptr };
    let (_, best) = Extractor::new(&eg.egraph, AstSize).find_best(eg.root);
    CString::new(best.pretty(width as usize)).unwrap().into_raw()
}
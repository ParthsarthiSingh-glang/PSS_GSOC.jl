#![recursion_limit = "256"]

mod herbie_rules;
mod my_rules;
mod to_rival;
mod discretization;

use egg::*;
use num_bigint::BigInt;
use num_rational::Ratio;
use num_traits::Zero;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::atomic::{AtomicBool, Ordering};

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
        "rep"   = Rep([Id; 3]),
        "rep-pow" = RepPow([Id; 3]),
        "rep-log" = RepLog([Id; 2]),

        // leaves
        Num(Constant),
        Symbol(egg::Symbol),

        // Other(egg::Symbol, Vec<Id>)
        Other(egg::Symbol, Vec<Id>),
    }
}

// ConstantFold — herbie/egg-herbie/src/math.rs
pub struct ConstantFold {
    pub unsound: AtomicBool,
    pub max_abs_exponent: Ratio<BigInt>,
    pub prune: bool,
}

impl Clone for ConstantFold {
    fn clone(&self) -> Self {
        let unsound = AtomicBool::new(self.unsound.load(Ordering::SeqCst));
        Self {
            unsound,
            max_abs_exponent: self.max_abs_exponent.clone(),
            prune: self.prune,
        }
    }
}

impl Default for ConstantFold {
    fn default() -> Self {
        Self {
            unsound: AtomicBool::new(false),
            max_abs_exponent: Ratio::new(BigInt::from(16), BigInt::from(1)),
            prune: true,
        }
    }
}

impl Analysis<MathLang> for ConstantFold {
    type Data = Option<(Constant, (PatternAst<MathLang>, Subst))>;

    fn make(egraph: &mut EGraph<MathLang, Self>, enode: &MathLang, _id: Id) -> Self::Data {
        let x = |i: &Id| egraph[*i].data.as_ref().map(|d| d.0.clone());
        let value = match enode {
            MathLang::Num(c)      => c.clone(),
            MathLang::Neg(a)      => -x(a)?,
            MathLang::Add([a, b]) => x(a)? + x(b)?,
            MathLang::Sub([a, b]) => x(a)? - x(b)?,
            MathLang::Mul([a, b]) => x(a)? * x(b)?,
            MathLang::Div([a, b]) => {
                let denom = x(b)?;
                if denom.is_zero() { return None; }
                x(a)? / denom
            }
            _ => return None,
        };

        let mut pattern: PatternAst<MathLang> = Default::default();
        let mut var_counter = 0;
        let mut subst: Subst = Default::default();
        enode.for_each(|child| {
            if let Some(d) = egraph[child].data.as_ref() {
                pattern.add(ENodeOrVar::ENode(MathLang::Num(d.0.clone())));
            } else {
                let var = ("?".to_string() + &var_counter.to_string()).parse().unwrap();
                pattern.add(ENodeOrVar::Var(var));
                subst.insert(var, child);
                var_counter += 1;
            }
        });
        let mut counter = 0;
        let mut head = enode.clone();
        head.update_children(|_child| {
            let res = Id::from(counter);
            counter += 1;
            res
        });
        pattern.add(ENodeOrVar::ENode(head));

        Some((value, (pattern, subst)))
    }

    fn merge(&mut self, to: &mut Self::Data, from: Self::Data) -> DidMerge {
        match (&to, from) {
            (None, None) => DidMerge(false, false),
            (Some(_), None) => DidMerge(false, true),
            (None, Some(c)) => {
                *to = Some(c);
                DidMerge(true, false)
            }
            (Some(a), Some(ref b)) => {
                if a.0 != b.0 && !self.unsound.swap(true, Ordering::SeqCst) {
                    log::warn!("Bad merge detected: {} != {}", a.0, b.0);
                }
                DidMerge(false, false)
            }
        }
    }

    fn modify(egraph: &mut EGraph<MathLang, Self>, id: Id) {
        if let Some((c, (pat, subst))) = egraph[id].data.clone() {
            egraph.union_instantiations(
                &pat,
                &format!("{}", c).parse().unwrap(),
                &subst,
                "metadata-eval".to_string(),
            );
        }
    }
}

pub struct EGraphWithRoot {
    pub egraph:      EGraph<MathLang, ConstantFold>,
    pub root:        Id,
    pub roots:       Vec<Id>, // herbie/egg-herbie/src/lib.rs Context.runner.roots
    pub stop_reason: u8,  // 0=Saturated 1=IterationLimit 2=NodeLimit 3=TimeLimit 4=Other
    pub iterations:  Vec<Iteration<()>>, // egg/src/run.rs Iteration.applied — rule fire counts per iteration
}

fn make_rules() -> Vec<Rewrite<MathLang, ConstantFold>> {
    herbie_rules::herbie_rules()
}

fn rep_removal_rules() -> Vec<Rewrite<MathLang, ConstantFold>> {
    vec![
        rewrite!("remove-rep"; "(rep ?a ?b ?c)" => "(/ ?a ?b)"),
        rewrite!("remove-rep-pow"; "(rep-pow ?a ?b ?c)" => "(pow ?a ?b)"),
        rewrite!("remove-rep-log"; "(rep-log ?a ?b)" => "(log ?a)"),
    ]
}

// // Egg Implementation of AstSize()
// pub struct AstSize;
// impl<L: Language> CostFunction<L> for AstSize {
//     type Cost = usize;
//     fn cost<C: FnMut(Id) -> usize>(&mut self, enode: &L, mut costs: C) -> usize {
//         enode.fold(1, |sum, id| sum.saturating_add(costs(id)))
//     }
// }

struct AstWithRep;
impl CostFunction<MathLang> for AstWithRep {
    type Cost = usize;
    fn cost<C>(&mut self, enode: &MathLang, mut costs: C) -> Self::Cost
    where C: FnMut(Id) -> Self::Cost {
        match enode {
            MathLang::Rep(_) | MathLang::RepPow(_) | MathLang::RepLog(_) => usize::MAX, // rep nodes
            _ => enode.fold(1, |sum, id| usize::saturating_add(sum, costs(id))),// Astsize()
            // please look into the costs of sqrt,sinh,cosh,etc.
        }
    }
}

// explanations enabled — herbie/egg-herbie/src/lib.rs egraph_create()
#[no_mangle]
pub extern "C" fn egraph_create(expr_ptr: *const c_char) -> *mut EGraphWithRoot {
    let expr_str = unsafe { CStr::from_ptr(expr_ptr) }.to_str().unwrap();
    let expr: RecExpr<MathLang> = expr_str.parse().unwrap();
    let mut egraph = EGraph::new(ConstantFold::default()).with_explanations_enabled();
    let root = egraph.add_expr(&expr);
    Box::into_raw(Box::new(EGraphWithRoot { egraph, root, roots: vec![root], stop_reason: 4, iterations: Vec::new() }))
}

// herbie/egg-herbie/src/lib.rs egraph_add_node — inserts a single enode into the EXISTING egraph from an operator name + already child ids.
#[no_mangle]
pub extern "C" fn egraph_add_node(ptr: *mut EGraphWithRoot, op_ptr: *const c_char, ids_ptr: *const u32, num_ids: u32) -> u32 {
    let eg = unsafe { &mut *ptr };
    let op = unsafe { CStr::from_ptr(op_ptr) }.to_str().unwrap();
    let ids: Vec<Id> = unsafe { std::slice::from_raw_parts(ids_ptr, num_ids as usize) }
        .iter()
        .map(|&i| Id::from(i as usize))
        .collect();
    let node = MathLang::from_op(op, ids).unwrap();
    let id = eg.egraph.add(node);
    usize::from(id) as u32
}

// herbie/egg-herbie/src/lib.rs egraph_add_root - an already-existing id gets as a tracket root 
#[no_mangle]
pub extern "C" fn egraph_add_root(ptr: *mut EGraphWithRoot, id: u32) {
    let eg = unsafe { &mut *ptr };
    eg.roots.push(Id::from(id as usize));
}

fn stop_reason_to_u8(reason: &Option<StopReason>) -> u8 {
    match reason {
        Some(StopReason::Saturated)         => 0,
        Some(StopReason::IterationLimit(_)) => 1,
        Some(StopReason::NodeLimit(_))      => 2,
        Some(StopReason::TimeLimit(_))      => 3,
        _                                   => 4,
    }
}

// node_limit=4000 matches Herbie's *node-limit* (herbie/src/config.rkt)
// no iter_limit — Herbie uses unlimited iterations, relies on node_limit + BackoffScheduler
#[no_mangle]
pub extern "C" fn egraph_saturate(ptr: *mut EGraphWithRoot) {
    let eg = unsafe { &mut *ptr };
    let expr = eg.egraph.id_to_expr(eg.root);
    let runner = Runner::default()
        .with_node_limit(4000)
        .with_hook(|r: &mut Runner<MathLang, ConstantFold>| {
           // eprintln!("[hook] iter={} nodes={} unsound={}", r.iterations.len(), r.egraph.total_size(), r.egraph.analysis.unsound.load(Ordering::SeqCst));
            if r.egraph.analysis.unsound.load(Ordering::SeqCst) {
                Err("Unsoundness detected".into())
            } else {
                Ok(())
            }
        })
        .with_egraph(eg.egraph.clone())
        .with_expr(&expr)
        .run(&make_rules());
    let stop = stop_reason_to_u8(&runner.stop_reason);
    let root = runner.roots[0];
    let iterations = runner.iterations.clone();
    let mut egraph = runner.egraph;
    // dont consider rep rules in future results
    for rule in rep_removal_rules() {
        let matches = rule.search(&egraph);
        rule.apply(&mut egraph, &matches);
        egraph.rebuild();
    }
    eg.stop_reason = stop;
    eg.root        = egraph.find(root);
    eg.egraph      = egraph;
    eg.iterations  = iterations;
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
    let (_, best) = Extractor::new(&eg.egraph, AstWithRep).find_best(eg.root);
    CString::new(best.to_string()).unwrap().into_raw()
}

// free the CString returned by egraph_extract
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

#[no_mangle]
pub extern "C" fn egraph_size(ptr: *mut EGraphWithRoot) -> u32 {
    let eg = unsafe { &*ptr };
    eg.egraph.number_of_classes() as u32
}

#[no_mangle]
pub extern "C" fn egraph_eclass_size(ptr: *mut EGraphWithRoot, id: u32) -> u32 {
    let eg = unsafe { &*ptr };
    eg.egraph[Id::from(id as usize)].nodes.len() as u32
}

#[no_mangle]
pub extern "C" fn egraph_find(ptr: *mut EGraphWithRoot, id: u32) -> u32 {
    let eg = unsafe { &*ptr };
    usize::from(eg.egraph.find(Id::from(id as usize))) as u32
}

#[no_mangle]
pub extern "C" fn egraph_root_id(ptr: *mut EGraphWithRoot) -> u32 {
    let eg = unsafe { &*ptr };
    usize::from(eg.root) as u32
}

#[no_mangle]
pub extern "C" fn egraph_total_size(ptr: *mut EGraphWithRoot) -> u32 {
    let eg = unsafe { &*ptr };
    eg.egraph.total_size() as u32
}

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

// please look in this later : 
// herbie/egg-herbie/src/lib.rs: egraph_get_eclasse
#[no_mangle]
pub extern "C" fn egraph_get_eclasses(ptr: *mut EGraphWithRoot, ids_ptr: *mut u32) {
    let eg = unsafe { &*ptr };
    let mut ids: Vec<u32> = eg.egraph
        .classes()
        .map(|c| usize::from(eg.egraph.find(c.id)) as u32)
        .collect::<std::collections::HashSet<u32>>()
        .into_iter()
        .collect();
    ids.sort();
    for (i, id) in ids.iter().enumerate() {
        unsafe { std::ptr::write(ids_ptr.offset(i as isize), *id) };
    }
}

// number of true canonical eclasses after union-find merges
#[no_mangle]
pub extern "C" fn egraph_num_classes(ptr: *mut EGraphWithRoot) -> u32 {
    let eg = unsafe { &*ptr };
    eg.egraph
        .classes()
        .map(|c| eg.egraph.find(c.id))
        .collect::<std::collections::HashSet<_>>()
        .len() as u32
}

// true if ConstantFold::merge ever saw two conflicting constant values
// for the same eclass during saturation (see ConstantFold::unsound)
#[no_mangle]
pub extern "C" fn egraph_unsound(ptr: *mut EGraphWithRoot) -> bool {
    let eg = unsafe { &*ptr };
    eg.egraph.analysis.unsound.load(Ordering::SeqCst)
}

// egg/src/run.rs Iteration.applied — rule name -> total times applied,
// summed across every iteration of the last egraph_saturate call
#[no_mangle]
pub extern "C" fn egraph_rule_stats(ptr: *mut EGraphWithRoot) -> *mut c_char {
    let eg = unsafe { &*ptr };
    let mut totals: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
    for iter in &eg.iterations {
        for (name, count) in &iter.applied {
            *totals.entry(name.to_string()).or_insert(0) += count;
        }
    }
    let mut pairs: Vec<(String, usize)> = totals.into_iter().collect();
    pairs.sort_by(|a, b| b.1.cmp(&a.1));
    let mut result = String::new();
    for (name, count) in pairs {
        result.push_str(&format!("{}: {}\n", name, count));
    }
    CString::new(result).unwrap().into_raw()
}

#[no_mangle]
pub extern "C" fn egraph_pretty_extract(ptr: *mut EGraphWithRoot, width: u32) -> *mut c_char {
    let eg = unsafe { &*ptr };
    let (_, best) = Extractor::new(&eg.egraph, AstWithRep).find_best(eg.root);
    CString::new(best.pretty(width as usize)).unwrap().into_raw()
}

#[no_mangle]
pub extern "C" fn egraph_id_to_expr(ptr: *mut EGraphWithRoot, id: u32) -> *mut c_char {
    let eg = unsafe { &*ptr };
    let expr = eg.egraph.id_to_expr(Id::from(id as usize));
    CString::new(expr.to_string()).unwrap().into_raw()
}

// herbie/egg-herbie/src/lib.rs egraph_get_proof
#[no_mangle]
pub extern "C" fn egraph_get_proof(ptr: *mut EGraphWithRoot, expr_ptr: *const c_char, goal_ptr: *const c_char) -> *mut c_char {
    let eg = unsafe { &mut *ptr };
    let expr: RecExpr<MathLang> = unsafe { CStr::from_ptr(expr_ptr) }.to_str().unwrap().parse().unwrap();
    let goal: RecExpr<MathLang> = unsafe { CStr::from_ptr(goal_ptr) }.to_str().unwrap().parse().unwrap();
    let string = eg.egraph
        .explain_equivalence(&expr, &goal)
        .get_string_with_let()
        .replace('\n', " ");
    CString::new(string).unwrap().into_raw()
}

// returns all enodes inside a given eclass as s-expr's
// egg stores enodes in egraph[id].nodes as a Vec<MathLang>
#[no_mangle]
pub extern "C" fn egraph_eclass_enodes(ptr: *mut EGraphWithRoot, id: u32) -> *mut c_char {
    let eg = unsafe { &*ptr };
    let eclass_id = Id::from(id as usize);
    let eclass = &eg.egraph[eclass_id];
    let mut result = String::new();
    
    // 1. Create the real Extractor ONCE up here!
    let mut extractor = Extractor::new(&eg.egraph, AstWithRep);

    for enode in &eclass.nodes {
        if matches!(enode, MathLang::Rep(_) | MathLang::RepPow(_) | MathLang::RepLog(_)) {
            continue;
        }
        // show operator with raw child eclass ids
        let s = format!("{}", enode);
        let children: Vec<String> = enode.children()
            .iter()
            .map(|child_id| {
                let (_, child_expr) = extractor.find_best(*child_id);
                child_expr.to_string()
            })
            .collect();
        let full = if children.is_empty() {
            s
        } else {
            format!("({} {})", s, children.join(" "))
        };
        result.push_str(&full);
        result.push('\n');
    }
    CString::new(result).unwrap().into_raw()
}

// dump egraph to a .dot file for visualization
// egg/src/dot.rs
#[no_mangle]
pub extern "C" fn egraph_dump_dot(ptr: *mut EGraphWithRoot, path_ptr: *const c_char) {
    let eg = unsafe { &*ptr };
    let path = unsafe { CStr::from_ptr(path_ptr) }.to_str().unwrap();
    eg.egraph.dot().to_dot(path).unwrap();
}


// Converts our MathLang (egg) expressions into rival3 Expr AST.
// Reference: rival3/src/eval/ops.rs (Expr variant list) and rival3/src/eval/macros.rs 


use crate::MathLang;
use egg::{RecExpr, Id};
use rival::Expr;
use std::str::FromStr;

pub fn mathlang_to_rival(expr: &RecExpr<MathLang>, id: Id) -> Expr {
    let node = &expr[id];
    match node {
        // leaves
        MathLang::Num(c) => {
            // Constant = num_rational::BigRational 
            // rival3 wants rug::Rational (bignum crate) - convert via string 
            let numer = rug::Integer::from_str(&c.numer().to_string()).unwrap();
            let denom = rug::Integer::from_str(&c.denom().to_string()).unwrap();
            Expr::Rational(rug::Rational::from((numer, denom)))
        }
        MathLang::Symbol(s) => Expr::Var(s.to_string()),

        // unary 
        MathLang::Neg(a)   => Expr::Neg(Box::new(mathlang_to_rival(expr, *a))),
        MathLang::Sqrt(a)  => Expr::Sqrt(Box::new(mathlang_to_rival(expr, *a))),
        MathLang::Fabs(a)  => Expr::Fabs(Box::new(mathlang_to_rival(expr, *a))),
        MathLang::Ceil(a)  => Expr::Ceil(Box::new(mathlang_to_rival(expr, *a))),
        MathLang::Floor(a) => Expr::Floor(Box::new(mathlang_to_rival(expr, *a))),
        MathLang::Round(a) => Expr::Round(Box::new(mathlang_to_rival(expr, *a))),
        MathLang::Log(a)   => Expr::Log(Box::new(mathlang_to_rival(expr, *a))),
        MathLang::Cbrt(a)  => Expr::Cbrt(Box::new(mathlang_to_rival(expr, *a))),

        // binary 
        MathLang::Add([a, b]) => Expr::Add(Box::new(mathlang_to_rival(expr, *a)), Box::new(mathlang_to_rival(expr, *b))),
        MathLang::Sub([a, b]) => Expr::Sub(Box::new(mathlang_to_rival(expr, *a)), Box::new(mathlang_to_rival(expr, *b))),
        MathLang::Mul([a, b]) => Expr::Mul(Box::new(mathlang_to_rival(expr, *a)), Box::new(mathlang_to_rival(expr, *b))),
        MathLang::Div([a, b]) => Expr::Div(Box::new(mathlang_to_rival(expr, *a)), Box::new(mathlang_to_rival(expr, *b))),
        MathLang::Pow([a, b]) => Expr::Pow(Box::new(mathlang_to_rival(expr, *a)), Box::new(mathlang_to_rival(expr, *b))),

        //  Other(sym, args) : everything not a named MathLang
        MathLang::Other(sym, args) => {
            let name = sym.as_str();
            let a = || Box::new(mathlang_to_rival(expr, args[0]));
            let b = || Box::new(mathlang_to_rival(expr, args[1]));
            match (name, args.len()) {
                ("sin", 1)  => Expr::Sin(a()),
                ("cos", 1)  => Expr::Cos(a()),
                ("tan", 1)  => Expr::Tan(a()),
                ("asin", 1) => Expr::Asin(a()),
                ("acos", 1) => Expr::Acos(a()),
                ("atan", 1) => Expr::Atan(a()),
                ("sinh", 1) => Expr::Sinh(a()),
                ("cosh", 1) => Expr::Cosh(a()),
                ("tanh", 1) => Expr::Tanh(a()),
                ("exp", 1)  => Expr::Exp(a()),
                ("copysign", 2) => Expr::Copysign(a(), b()),
                ("fmin", 2) => Expr::Fmin(a(), b()),
                ("fmax", 2) => Expr::Fmax(a(), b()),
                ("atan2", 2) => Expr::Atan2(a(), b()),
                ("hypot", 2) => Expr::Hypot(a(), b()),
                _ => panic!("Other operator: {} (arity {}) not in to_rival.rs list", name, args.len()),
            }
        }
        
        MathLang::Rep(_) | MathLang::RepPow(_) | MathLang::RepLog(_) => {
            panic!("Rep node reached converter");
        }
    }
}

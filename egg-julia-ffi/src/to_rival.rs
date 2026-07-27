// Converts our MathLang (egg) expressions into rival3 Expr AST.
// Reference: rival3/src/eval/ops.rs (Expr variant list) and rival3/src/eval/macros.rs


use crate::MathLang;
use egg::{RecExpr, Id};
use rival::Expr;
use std::str::FromStr;

// Returns Err(message) instead of panicking on an operator
pub fn mathlang_to_rival(expr: &RecExpr<MathLang>, id: Id) -> Result<Expr, String> {
    let node = &expr[id];
    match node {
        // leaves
        MathLang::Num(c) => {
            // Constant = num_rational::BigRational
            // rival3 wants rug::Rational (bignum crate) - convert via string
            let numer = rug::Integer::from_str(&c.numer().to_string()).unwrap();
            let denom = rug::Integer::from_str(&c.denom().to_string()).unwrap();
            Ok(Expr::Rational(rug::Rational::from((numer, denom))))
        }
        MathLang::Symbol(s) => {
            let name = s.to_string();
            match name.as_str() {
                "PI" => Ok(Expr::Pi),
                "E"  => Ok(Expr::E),
                _ => Ok(Expr::Var(name)),
            }
        }

        // unary
        MathLang::Neg(a)   => Ok(Expr::Neg(Box::new(mathlang_to_rival(expr, *a)?))),
        MathLang::Sqrt(a)  => Ok(Expr::Sqrt(Box::new(mathlang_to_rival(expr, *a)?))),
        MathLang::Fabs(a)  => Ok(Expr::Fabs(Box::new(mathlang_to_rival(expr, *a)?))),
        MathLang::Ceil(a)  => Ok(Expr::Ceil(Box::new(mathlang_to_rival(expr, *a)?))),
        MathLang::Floor(a) => Ok(Expr::Floor(Box::new(mathlang_to_rival(expr, *a)?))),
        MathLang::Round(a) => Ok(Expr::Round(Box::new(mathlang_to_rival(expr, *a)?))),
        MathLang::Log(a)   => Ok(Expr::Log(Box::new(mathlang_to_rival(expr, *a)?))),
        MathLang::Cbrt(a)  => Ok(Expr::Cbrt(Box::new(mathlang_to_rival(expr, *a)?))),

        // binary
        MathLang::Add([a, b]) => Ok(Expr::Add(Box::new(mathlang_to_rival(expr, *a)?), Box::new(mathlang_to_rival(expr, *b)?))),
        MathLang::Sub([a, b]) => Ok(Expr::Sub(Box::new(mathlang_to_rival(expr, *a)?), Box::new(mathlang_to_rival(expr, *b)?))),
        MathLang::Mul([a, b]) => Ok(Expr::Mul(Box::new(mathlang_to_rival(expr, *a)?), Box::new(mathlang_to_rival(expr, *b)?))),
        MathLang::Div([a, b]) => Ok(Expr::Div(Box::new(mathlang_to_rival(expr, *a)?), Box::new(mathlang_to_rival(expr, *b)?))),
        MathLang::Pow([a, b]) => Ok(Expr::Pow(Box::new(mathlang_to_rival(expr, *a)?), Box::new(mathlang_to_rival(expr, *b)?))),

        //  Other(sym, args) : everything not a named MathLang
        MathLang::Other(sym, args) => {
            let name = sym.as_str();
            let a = |i: usize| -> Result<Box<Expr>, String> { Ok(Box::new(mathlang_to_rival(expr, args[i])?)) };
            match (name, args.len()) {
                ("fma", 3) => Ok(Expr::Fma(a(0)?, a(1)?, a(2)?)),
                ("sin", 1)  => Ok(Expr::Sin(a(0)?)),
                ("cos", 1)  => Ok(Expr::Cos(a(0)?)),
                ("tan", 1)  => Ok(Expr::Tan(a(0)?)),
                ("asin", 1) => Ok(Expr::Asin(a(0)?)),
                ("acos", 1) => Ok(Expr::Acos(a(0)?)),
                ("atan", 1) => Ok(Expr::Atan(a(0)?)),
                ("sinh", 1) => Ok(Expr::Sinh(a(0)?)),
                ("cosh", 1) => Ok(Expr::Cosh(a(0)?)),
                ("tanh", 1) => Ok(Expr::Tanh(a(0)?)),
                ("asinh", 1) => Ok(Expr::Asinh(a(0)?)),
                ("acosh", 1) => Ok(Expr::Acosh(a(0)?)),
                ("atanh", 1) => Ok(Expr::Atanh(a(0)?)),
                ("erf", 1)  => Ok(Expr::Erf(a(0)?)),
                ("erfc", 1) => Ok(Expr::Erfc(a(0)?)),
                ("abs", 1)  => Ok(Expr::Fabs(a(0)?)),
                ("exp", 1)  => Ok(Expr::Exp(a(0)?)),
                ("log1p", 1) => Ok(Expr::Log1p(a(0)?)),
                ("expm1", 1) => Ok(Expr::Expm1(a(0)?)),
                ("copysign", 2) => Ok(Expr::Copysign(a(0)?, a(1)?)),
                ("fmin", 2) => Ok(Expr::Fmin(a(0)?, a(1)?)),
                ("fmax", 2) => Ok(Expr::Fmax(a(0)?, a(1)?)),
                ("atan2", 2) => Ok(Expr::Atan2(a(0)?, a(1)?)),
                ("hypot", 2) => Ok(Expr::Hypot(a(0)?, a(1)?)),
                ("remainder", 2) => Ok(Expr::Remainder(a(0)?, a(1)?)),
                _ => Err(format!("Other operator: {} (arity {}) not in to_rival.rs list", name, args.len())),
            }
        }

        MathLang::Rep(_) | MathLang::RepPow(_) | MathLang::RepLog(_) => {
            Err("Rep node reached converter".to_string())
        }
    }
}

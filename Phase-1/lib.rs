#![recursion_limit = "256"]

use egg::*;
use ordered_float::NotNan;

pub type Constant = NotNan<f64>;//for having NonNan f64 in Eq , Ord 

define_language! {
    pub enum MathLang {

        // General Math - unary
        "uplus"   = UPlus(Id),
        "uminus"  = UMinus(Id),
        "sqrt"    = Sqrt(Id),
        "cbrt"    = Cbrt(Id),
        "abs"     = Abs(Id),
        "abs2"    = Abs2(Id),
        "inv"     = Inv(Id),
        "log"     = Log(Id),
        "log10"   = Log10(Id),
        "log2"    = Log2(Id),
        "log1p"   = Log1p(Id),
        "exp"     = Exp(Id),
        "exp2"    = Exp2(Id),
        "exp10"   = Exp10(Id),
        "expm1"   = Expm1(Id),
        "sin"     = Sin(Id),
        "cos"     = Cos(Id),
        "tan"     = Tan(Id),
        "sec"     = Sec(Id),
        "csc"     = Csc(Id),
        "cot"     = Cot(Id),
        "sind"    = Sind(Id),
        "cosd"    = Cosd(Id),
        "tand"    = Tand(Id),
        "secd"    = Secd(Id),
        "cscd"    = Cscd(Id),
        "cotd"    = Cotd(Id),
        "sinpi"   = Sinpi(Id),
        "cospi"   = Cospi(Id),
        "asin"    = Asin(Id),
        "acos"    = Acos(Id),
        "atan"    = Atan(Id),
        "asec"    = Asec(Id),
        "acsc"    = Acsc(Id),
        "acot"    = Acot(Id),
        "asind"   = Asind(Id),
        "acosd"   = Acosd(Id),
        "atand"   = Atand(Id),
        "asecd"   = Asecd(Id),
        "acscd"   = Acscd(Id),
        "acotd"   = Acotd(Id),
        "sinh"    = Sinh(Id),
        "cosh"    = Cosh(Id),
        "tanh"    = Tanh(Id),
        "sech"    = Sech(Id),
        "csch"    = Csch(Id),
        "coth"    = Coth(Id),
        "asinh"   = Asinh(Id),
        "acosh"   = Acosh(Id),
        "atanh"   = Atanh(Id),
        "asech"   = Asech(Id),
        "acsch"   = Acsch(Id),
        "acoth"   = Acoth(Id),
        "sinc"    = Sinc(Id),
        "deg2rad" = Deg2Rad(Id),
        "rad2deg" = Rad2Deg(Id),
        "mod2pi"  = Mod2Pi(Id),

        // General Math - binary
        "+"       = Add([Id; 2]),
        "-"       = Sub([Id; 2]),
        "*"       = Mul([Id; 2]),
        "/"       = Div([Id; 2]),
        "ldiv"    = LDiv([Id; 2]),
        "^"       = Pow([Id; 2]),
        "atan2"   = Atan2([Id; 2]),
        "hypot"   = Hypot([Id; 2]),
        "logb"    = LogB([Id; 2]),
        "ldexp"   = Ldexp([Id; 2]),
        "mod"     = Mod([Id; 2]),
        "rem"     = Rem([Id; 2]),
        "rem2pi"  = Rem2Pi([Id; 2]),
        "max"     = Max([Id; 2]),
        "min"     = Min([Id; 2]),

        // General Math - trinary
        "muladd"  = Muladd([Id; 3]),
        "fma"     = Fma([Id; 3]),
        "ifelse"  = Ifelse([Id; 3]),

        // SpecialFunctions - unary
        "gamma"        = Gamma(Id),
        "loggamma"     = Loggamma(Id),
        "erf"          = Erf(Id),
        "erfinv"       = Erfinv(Id),
        "erfc"         = Erfc(Id),
        "logerfc"      = Logerfc(Id),
        "erfcinv"      = Erfcinv(Id),
        "erfi"         = Erfi(Id),
        "erfcx"        = Erfcx(Id),
        "logerfcx"     = Logerfcx(Id),
        "dawson"       = Dawson(Id),
        "digamma"      = Digamma(Id),
        "invdigamma"   = Invdigamma(Id),
        "trigamma"     = Trigamma(Id),
        "airyai"       = Airyai(Id),
        "airyaiprime"  = Airyaiprime(Id),
        "airyaix"      = Airyaix(Id),
        "airyaiprimex" = Airyaiprimex(Id),
        "airybi"       = Airybi(Id),
        "airybiprime"  = Airybiprime(Id),
        "airybix"      = Airybix(Id),
        "airybiprimex" = Airybiprimex(Id),
        "besselj0"     = Besselj0(Id),
        "besselj1"     = Besselj1(Id),
        "bessely0"     = Bessely0(Id),
        "bessely1"     = Bessely1(Id),
        "sinint"       = Sinint(Id),
        "cosint"       = Cosint(Id),
        "ellipk"       = Ellipk(Id),
        "ellipe"       = Ellipe(Id),
        "expint"       = Expint(Id),

        // SpecialFunctions - binary
        "erf2"       = Erf2([Id; 2]),
        "besselj"    = Besselj([Id; 2]),
        "besseljx"   = Besseljx([Id; 2]),
        "besseli"    = Besseli([Id; 2]),
        "besselix"   = Besselix([Id; 2]),
        "bessely"    = Bessely([Id; 2]),
        "besselyx"   = Besselyx([Id; 2]),
        "besselk"    = Besselk([Id; 2]),
        "besselkx"   = Besselkx([Id; 2]),
        "besselh"    = Besselh([Id; 2]),
        "besselhx"   = Besselhx([Id; 2]),
        "hankelh1"   = Hankelh1([Id; 2]),
        "hankelh1x"  = Hankelh1x([Id; 2]),
        "hankelh2"   = Hankelh2([Id; 2]),
        "hankelh2x"  = Hankelh2x([Id; 2]),
        "polygamma"  = Polygamma([Id; 2]),
        "beta"       = Beta([Id; 2]),
        "logbeta"    = Logbeta([Id; 2]),
        "expint2"    = Expint2([Id; 2]),
        "zeta"       = Zeta([Id; 2]),

        // NaNMath - unary
        "nan_sqrt"   = NanSqrt(Id),
        "nan_sin"    = NanSin(Id),
        "nan_cos"    = NanCos(Id),
        "nan_tan"    = NanTan(Id),
        "nan_asin"   = NanAsin(Id),
        "nan_acos"   = NanAcos(Id),
        "nan_acosh"  = NanAcosh(Id),
        "nan_atanh"  = NanAtanh(Id),
        "nan_log"    = NanLog(Id),
        "nan_log2"   = NanLog2(Id),
        "nan_log10"  = NanLog10(Id),
        "nan_log1p"  = NanLog1p(Id),
        "nan_lgamma" = NanLgamma(Id),

        // NaNMath - binary
        "nan_pow"    = NanPow([Id; 2]),
        "nan_max"    = NanMax([Id; 2]),
        "nan_min"    = NanMin([Id; 2]),

        // LogExpFunctions - unary
        "xlogx"      = Xlogx(Id),
        "logistic"   = Logistic(Id),
        "logit"      = Logit(Id),
        "log1psq"    = Log1psq(Id),
        "log1pexp"   = Log1pexp(Id),
        "log1mexp"   = Log1mexp(Id),
        "log2mexp"   = Log2mexp(Id),
        "logexpm1"   = Logexpm1(Id),
        "log1pmx"    = Log1pmx(Id),
        "logmxp1"    = Logmxp1(Id),

        // LogExpFunctions - binary
        "xlogy"      = Xlogy([Id; 2]),
        "logaddexp"  = Logaddexp([Id; 2]),
        "logsubexp"  = Logsubexp([Id; 2]),
        "xlog1py"    = Xlog1py([Id; 2]),

        // leaves
        Num(Constant),
        Symbol(egg::Symbol),
    }
}

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn egraph_create(expr_ptr: *const c_char) -> *mut EGraph<MathLang, ()> {
    let expr_str = unsafe { CStr::from_ptr(expr_ptr) }.to_str().unwrap();
    let expr: RecExpr<MathLang> = expr_str.parse().unwrap();
    let mut egraph = EGraph::new(());
    egraph.add_expr(&expr);
}   

//add egraph_saturate, egraph_extract here :
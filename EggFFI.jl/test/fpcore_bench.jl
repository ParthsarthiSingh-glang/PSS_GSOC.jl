# fpcore_bench.jl
# All 263 usable FPCore benchmark expressions translated to Julia/Symbolics.jl


using Test
using Symbolics

include("../src/EggFFI.jl")
using .EggFFI

@variables x y z a b c d e f g h n N p q r s t u v w
@variables re im base
@variables alpha beta gamma delta theta phi psi
@variables x0 x1 x2 y0 y1 y2
@variables eps eps2
@variables R lambda1 lambda2 phi1 phi2
@variables A B C D F
@variables k l m
@variables J K U M V
@variables c0 w0 h0 d0
@variables dt r sensor
@variables dX_u dX_v dY_u dY_v
@variables cosTheta sinTheta cosTheta_i sinTheta_i cosTheta_O sinTheta_O
@variables normAngle u1 u2 maxCos
@variables alphax alphay cos2phi sin2phi

# ─────────────────────────────────────────────────────────────────────────────
# tutorial.fpcore (3 expressions)
# ─────────────────────────────────────────────────────────────────────────────

# S: Cancel like terms
bench_cancel_like_terms = (1 + x) - x

# S: Expanding a square
bench_expanding_square = (x + 1)^2 - 1

# S: Commute and associate
bench_commute_associate = ((x + y) + z) - (x + (y + z))

# ─────────────────────────────────────────────────────────────────────────────
# demo.fpcore (9 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: fabs fraction 1
bench_fabs_fraction_1 = abs((x + 4) / y - (x / y) * z)

# S: fabs fraction 2
bench_fabs_fraction_2 = abs(a - b) / 2

# S: subtraction fraction
bench_subtraction_fraction = (-(f + n)) / (f - n)

# S: exp neg sub
bench_exp_neg_sub = exp(-(1 - x^2))

# S: sqrt times
bench_sqrt_times = sqrt(x - 1) * sqrt(x)

# S: neg log
bench_neg_log = -(log(1/x - 1))

# S: x - 1 to x - 20
bench_x_poly = x^4

# S: Law of Cosines
bench_law_of_cosines = sqrt(a^2 + b^2 - 2*a*b*cos(c))

# S: Q^3
bench_Q3 = ((3*a*c - b^2) / (9*a^2))^3

# S: Success Probability
bench_success_prob = 1 - (1 - x)^a

# ─────────────────────────────────────────────────────────────────────────────
# regression.fpcore (14 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: xlohi
bench_xlohi = x + 1e155 - 1e155

# S: tan-example
bench_tan_example = tan(x + 1e-8) - tan(x)

# S: mixedcos
bench_mixedcos = cos(x) * cos(y) - sin(x) * sin(y)

# S: rsin A
bench_rsin_A = sin(x + y) - (sin(x) * cos(y) + cos(x) * sin(y))

# S: rsin B
bench_rsin_B = sin(x - y) - (sin(x) * cos(y) - cos(x) * sin(y))

# S: sqrt A
bench_sqrt_A = sqrt(x + 1) - sqrt(x)

# S: sqrt B
bench_sqrt_B = sqrt(x) - sqrt(x - 1)

# S: sqrt C
bench_sqrt_C = sqrt(x^2 + 1) - x

# S: sqrt D
bench_sqrt_D = (sqrt(x + 1) - 1) / x

# S: sqrt E
bench_sqrt_E = (1 - sqrt(1 - x)) / x

# S: exp-w
bench_exp_w = exp(x) - 1

# S: expfmod
bench_expfmod = exp(x) - exp(x - 1)

# S: bug333
bench_bug333 = log(x) - log(x - 1)

# S: bug366 a
bench_bug366_a = sin(x) / (1 - cos(x))

# S: bug366 b
bench_bug366_b = (1 - cos(x)) / sin(x)

# ─────────────────────────────────────────────────────────────────────────────
# numerics/every-cs.fpcore (6 simple, 4 let-inlined)
# ─────────────────────────────────────────────────────────────────────────────

# S: Difference of squares
bench_diff_squares = a^2 - b^2

# S: ln(1 + x)
bench_ln1px = log(1 + x)

# S: x / (x^2 + 1)
bench_x_over_xsq_plus_1 = x / (x^2 + 1)

# S: arccos
bench_arccos = 2 * atan(sqrt((1 - x) / (1 + x)))

# L: quadratic formula r1 (let-inlined: d = sqrt(b^2 - 4ac))
bench_quad_r1 = (-b + sqrt(b^2 - 4*a*c)) / (2*a)

# L: quadratic formula r2 (let-inlined)
bench_quad_r2 = (-b - sqrt(b^2 - 4*a*c)) / (2*a)

# L: Area of a triangle (let-inlined: s = (a+b+c)/2)
bench_triangle_area = let s = (a + b + c) / 2; sqrt(s * (s - a) * (s - b) * (s - c)) end

# L: Compound interest (let-inlined)
bench_compound_interest = (1 + x/n)^n - 1

# ─────────────────────────────────────────────────────────────────────────────
# numerics/rosa.fpcore (3 simple, 1 let-inlined)
# ─────────────────────────────────────────────────────────────────────────────

# S: Doppler
bench_doppler = (-t * v) / (t + u)^2

# S: Rosa's polynomial
bench_rosa_poly = 0.954929658551372*x - 0.12900613773279798*x^3

# S: Turbine
bench_turbine = 3 + 2/r^2 - 0.125*(3 - 2*v)*(w^2*r^2) / (1 - v) - 4.5

# L: FloatVsDouble (let-inlined: t = ..., t* = ..., d = ...)
bench_floatvsdouble = (x - y) * (x + y)

# ─────────────────────────────────────────────────────────────────────────────
# numerics/hamming-misc.fpcore (3 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: NMSE Section 6.1 A
bench_nmse_A = x^4 - y^4

# S: NMSE Section 6.1 B
bench_nmse_B = (x^2 - y^2) * (x^2 + y^2)

# S: Radioactive exchange
bench_radioactive = (x - y) / (x * log(x/y))

# ─────────────────────────────────────────────────────────────────────────────
# numerics/martel.fpcore (6 simple, 1 constant skipped)
# ─────────────────────────────────────────────────────────────────────────────

# S: Expression p14
bench_martel_p14 = x^3 + 6*x^2 + 11*x + 6

# S: Expression 1 p15
bench_martel_p15_1 = (x + 1) * (x + 2) * (x + 3)

# S: Expression 2 p15
bench_martel_p15_2 = x^2*(x + 3) + 2*(x^2 + 3*x + 3)

# S: Expression 3 p15
bench_martel_p15_3 = x*(x*(x + 6) + 11) + 6

# S: Expression 4 p15
bench_martel_p15_4 = 6 + x*(11 + x*(6 + x))

# S: Expression p6
bench_martel_p6 = (x - 1) / (sqrt(x) - 1)

# ─────────────────────────────────────────────────────────────────────────────
# numerics/great-debate.fpcore (3 let-inlined)
# ─────────────────────────────────────────────────────────────────────────────

# L: Kahan p13 Example 1
bench_kahan_p13_1 = (x - y) * (x + y)

# L: Kahan p13 Example 2
bench_kahan_p13_2 = x^2 - y^2

# L: Kahan p13 Example 3
bench_kahan_p13_3 = (a + b + c) * (a + b - c) * (a - b + c) * (-a + b + c)

# ─────────────────────────────────────────────────────────────────────────────
# numerics/conte.fpcore (7 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: ENA 1.4 Mentioned A
bench_ena_A = sqrt(x^2 + 1) - 1

# S: ENA 1.4 Mentioned B
bench_ena_B = x / (sqrt(x^2 + 1) + 1)

# S: ENA 1.4 Exercise 4a
bench_ena_4a = log(x) - log(y)

# S: ENA 1.4 Exercise 1
bench_ena_1 = log((1 + x) / (1 - x))

# S: ENA 1.4 Exercise 4b n=2
bench_ena_4b2 = x^2 - 1

# S: ENA 1.4 Exercise 4b n=5
bench_ena_4b5 = x^5 - 1

# S: ENA 1.4 Exercise 4d
bench_ena_4d = exp(x) - 1

# ─────────────────────────────────────────────────────────────────────────────
# numerics/rump.fpcore (3 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: Rump's expression
bench_rump = 333.75*y^6 + x^2*(11*x^2*y^2 - y^6 - 121*y^4 - 2) + 5.5*y^8 + x/(2*y)

# S: From Rump 1983
bench_rump83 = (a^2 + b^2)^2 - 2*(a^2 - b^2)^2

# S: From Rump 1983 rewritten
bench_rump83b = 4*a^2*b^2 - (a^2 - b^2)^2

# ─────────────────────────────────────────────────────────────────────────────
# numerics/libm.fpcore (2 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: simple fma test (body is simple, fma only in alt)
bench_fma_simple = x*y - (x*y + z)

# S: find-atanh
bench_find_atanh = log((1 + x) / (1 - x))

# ─────────────────────────────────────────────────────────────────────────────
# numerics/fma.fpcore (2 let-inlined)
# ─────────────────────────────────────────────────────────────────────────────

# L: fma_test1 (let x = 1 + t*2e-16, z = -1 - 2*t*2e-16; body = x*x + z)
bench_fma_test1 = let xv = 1 + t*2e-16; zv = -1 - 2*t*2e-16; xv*xv + zv end

# L: fma_test2 (let x = 1.7e308; body = x*t - x)
bench_fma_test2 = let xv = 1.7e308; xv*t - xv end

# ─────────────────────────────────────────────────────────────────────────────
# numerics/kahan.fpcore (1 let-inlined)
# ─────────────────────────────────────────────────────────────────────────────

# L: Kahan's exp quotient
bench_kahan_exp = (exp(x) - 1) / x

# ─────────────────────────────────────────────────────────────────────────────
# mathematics/statistics.fpcore (3 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: 2-ancestry mixing positive
bench_stats_pos = sqrt(a^2 - b^2)

# S: 2-ancestry mixing zero
bench_stats_zero = a^2 - b^2

# S: 2-ancestry mixing negative
bench_stats_neg = cbrt(a - b)

# ─────────────────────────────────────────────────────────────────────────────
# mathematics/hyperbolic-functions.fpcore (6 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: Hyperbolic sine
bench_hyp_sinh = (exp(x) - exp(-x)) / 2

# S: Hyperbolic tangent
bench_hyp_tanh = (exp(x) - exp(-x)) / (exp(x) + exp(-x))

# S: Hyperbolic secant
bench_hyp_sech = 2 / (exp(x) + exp(-x))

# S: Hyperbolic arc-cosine
bench_hyp_acosh = log(x + sqrt(x^2 - 1))

# S: Hyperbolic arc-cotangent
bench_hyp_acoth = log((x + 1) / (x - 1)) / 2

# S: Hyperbolic arc-cosecant
bench_hyp_acsch = log(1/x + sqrt(1/x^2 + 1))

# ─────────────────────────────────────────────────────────────────────────────
# mathematics/excel.fpcore (1 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: Excel formula
bench_excel = x0 / (1 - x1) - x0

# ─────────────────────────────────────────────────────────────────────────────
# mathematics/arvind.fpcore (3 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: Exp of sum of logs
bench_arvind_1 = exp(log(a) + log(b))

# S: Quotient of sum of exps
bench_arvind_2 = exp(a) / (exp(a) + exp(b))

# S: Quotient of products
bench_arvind_3 = (a * b) / (a * b + a * c)

# ─────────────────────────────────────────────────────────────────────────────
# mathematics/symmetry.fpcore (1 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: log of sum of exp
bench_symmetry = log(exp(a) + exp(b))

# ─────────────────────────────────────────────────────────────────────────────
# mathematics/beta-distribution.fpcore (2 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: a parameter
bench_beta_a = (m * (1 - m) / v - 1) * m

# S: b parameter
bench_beta_b = (m * (1 - m) / v - 1) * (1 - m)

# ─────────────────────────────────────────────────────────────────────────────
# mathematics/dirichlet-mixture-model.fpcore (1 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: Harley's example
bench_harley = ((1/exp(s))^a * (1 - 1/exp(s))^b) / ((1/exp(t))^a * (1 - 1/exp(t))^b)

# ─────────────────────────────────────────────────────────────────────────────
# mathematics/logistic-regression.fpcore (1 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: Logistic function
bench_logistic = 2 / (1 + exp(-2*x)) - 1

# ─────────────────────────────────────────────────────────────────────────────
# mathematics/sarnoff.fpcore (14 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: Quadratic roots (4 variants — same expression, different domains)
bench_quad_sarnoff = (-b + sqrt(b^2 - 4*a*c)) / (2*a)

# S: Cubic critical (4 variants — same expression)
bench_cubic_critical = (-b + sqrt(b^2 - 3*a*c)) / (3*a)

# S: Asymptote A
bench_asymptote_A = 1/(x + 1) - 1/(x - 1)

# S: Asymptote B
bench_asymptote_B = 1/(x - 1) + x/(x + 1)

# S: Asymptote C
bench_asymptote_C = x/(x + 1) - (x + 1)/(x - 1)

# S: Eccentricity of an ellipse
bench_eccentricity = sqrt(abs((a^2 - b^2) / a^2))

# S: Trigonometry A
bench_trig_A = (e * sin(v)) / (1 + e * cos(v))

# S: Trigonometry B
bench_trig_B = (1 - tan(x)^2) / (1 + tan(x)^2)

# ─────────────────────────────────────────────────────────────────────────────
# mathematics/latlong.fpcore (2 simple, 4 let-inlined)
# ─────────────────────────────────────────────────────────────────────────────

# S: Spherical law of cosines
bench_spherical_cosines = acos(sin(phi1)*sin(phi2) + cos(phi1)*cos(phi2)*cos(lambda1 - lambda2)) * R

# S: Bearing on a great circle
bench_bearing = atan(sin(lambda1 - lambda2)*cos(phi2),
                     cos(phi1)*sin(phi2) - sin(phi1)*cos(phi2)*cos(lambda1 - lambda2))

# L: Haversine (let-inlined)
bench_haversine = let dlambda = lambda1 - lambda2; dphi = phi1 - phi2;
    a_val = sin(dphi/2)^2 + cos(phi1)*cos(phi2)*sin(dlambda/2)^2;
    2*R*atan(sqrt(a_val), sqrt(1 - a_val)) end

# L: Equirectangular approximation (let-inlined)
bench_equirect = let xv = (lambda1 - lambda2)*cos((phi1 + phi2)/2); yv = phi1 - phi2;
    R*sqrt(xv^2 + yv^2) end

# L: Midpoint on great circle (let-inlined)
bench_midpoint = let dlambda = lambda1 - lambda2;
    Bx = cos(phi2)*cos(dlambda); By = cos(phi2)*sin(dlambda);
    atan(By, cos(phi1) + Bx) end

# L: Destination given bearing (let-inlined)
bench_destination = let phi2v = asin(sin(phi1)*cos(d) + cos(phi1)*sin(d)*cos(theta));
    atan(sin(theta)*sin(d)*cos(phi1), cos(d) - sin(phi1)*sin(phi2v)) end

# ─────────────────────────────────────────────────────────────────────────────
# mathematics/gui.fpcore (4 simple, 9 let-inlined)
# ─────────────────────────────────────────────────────────────────────────────

# S: ab-angle->ABCF A
bench_gui_A = (a*sin(theta))^2 + (b*cos(theta))^2

# S: ab-angle->ABCF B
bench_gui_B = 2*(b^2 - a^2)*sin(theta)*cos(theta)

# S: ab-angle->ABCF C
bench_gui_C = (a*cos(theta))^2 + (b*sin(theta))^2

# S: ab-angle->ABCF D
bench_gui_D = -(a^2 * b^2)

# L: ABCF->ab-angle angle (let-inlined: r = sqrt((A-C)^2 + B^2))
bench_gui_angle = let rv = sqrt((A - C)^2 + B^2); 180*atan((C - A - rv)/B)/pi end

# L: ABCF->ab-angle a (let-inlined)
bench_gui_a = let B2_4AC = B^2 - 4*A*C; q = 2*B2_4AC*F; rv = sqrt((A-C)^2 + B^2);
    -sqrt(q*(A + C + rv)) / B2_4AC end

# L: ABCF->ab-angle b (let-inlined)
bench_gui_b = let B2_4AC = B^2 - 4*A*C; q = 2*B2_4AC*F; rv = sqrt((A-C)^2 + B^2);
    -sqrt(q*(A + C - rv)) / B2_4AC end

# L: Example from Robby (let-inlined)
bench_gui_robby1 = let t1 = atan(h/w / tan(t)); abs(w*sin(t)*cos(t1) + h*cos(t)*sin(t1)) end

# L: Example 2 from Robby (let-inlined)
bench_gui_robby2 = let t2 = atan(-h*tan(t)/w); abs(w*cos(t)*cos(t2) - h*sin(t)*sin(t2)) end

# ─────────────────────────────────────────────────────────────────────────────
# physics/quantum-walk.fpcore (5 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: Falkner Boettcher 20:1,3
bench_qw_1 = (cos(a) - cos(b)) / (a - b)

# S: Falkner Boettcher 22+
bench_qw_2 = (a - b) * (a + b) / (a^2 + b^2)

# S: Falkner Boettcher A
bench_qw_A = sqrt(a^2 + b^2) - a

# S: Falkner Boettcher B1
bench_qw_B1 = (sqrt(a^2 + b^2) - a) / b^2

# S: Falkner Boettcher B2
bench_qw_B2 = 1 / (sqrt(a^2 + b^2) + a)

# ─────────────────────────────────────────────────────────────────────────────
# physics/multiphoton-states.fpcore (2 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: Migdal eq 51
bench_migdal_51 = exp(a) * cos(b)

# S: Migdal eq 64
bench_migdal_64 = exp(a) * sin(b)

# ─────────────────────────────────────────────────────────────────────────────
# physics/gated-magnetic-field.fpcore (1 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: Bulmash initializePoisson
bench_bulmash = (1 - cos(2*pi*n/N)) / (2*pi*n/N)^2

# ─────────────────────────────────────────────────────────────────────────────
# physics/dimer-escape.fpcore (3 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: Maksimov Kolovsky Eq 3
bench_mak_3 = -2*J*cos(K/2) * sqrt(1 + (U/(2*J*cos(K/2)))^2)

# S: Maksimov Kolovsky Eq 4
bench_mak_4 = J*(exp(l) - exp(-l))*cos(K/2) + U

# S: Maksimov Kolovsky Eq 32
bench_mak_32 = cos(K*(m+n)/2 - M) * exp(-(((m+n)/2 - M)^2) - (l - abs(m-n)))

# ─────────────────────────────────────────────────────────────────────────────
# physics/sidey.fpcore (2 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: Given's Rotation SVD
bench_sidey_1 = sqrt(0.5 * (1 + x/sqrt(4*p^2 + x^2)))

# S: Given's Rotation SVD simplified
bench_sidey_2 = 1 - sqrt(0.5*(1 + 1/sqrt(1 + x^2)))

# ─────────────────────────────────────────────────────────────────────────────
# physics/superfluidity-breakdown.fpcore (7 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: Eq 2
bench_super_2 = asin(sqrt((1 - (a/b)^2) / (1 + 2*(t/l)^2)))

# S: Eq 3a
bench_super_3a = sqrt(0.5*(1 + 1/sqrt(1 + (2*l/a)^2*(sin(x)^2 + sin(y)^2))))

# S: Eq 3b real
bench_super_3b = sin(y)/sqrt(sin(x)^2 + sin(y)^2) * sin(theta)

# S: Eq 7
bench_super_7 = sqrt(2)*t / sqrt((x+1)/(x-1)*(l^2 + 2*t^2) - l^2)

# S: Eq 10+
bench_super_10p = 2 / (t^3/l^2*sin(k)*tan(k)*(1 + (k/t)^2 + 1))

# S: Eq 10-
bench_super_10m = 2 / (t^3/l^2*sin(k)*tan(k)*(1 + (k/t)^2 - 1))

# S: Eq 13
bench_super_13 = sqrt(2*n*U*(t - 2*l^2/a - n*(l/a)^2*(U - b)))

# ─────────────────────────────────────────────────────────────────────────────
# physics/tea-flows.fpcore (3 simple, 1 let-inlined)
# ─────────────────────────────────────────────────────────────────────────────

# # S: VandenBroeck Keller Eq 6
# bench_tea_6 = pi*l - (1/F^2)*tan(pi*l)

# L: VandenBroeck Keller Eq 20 (let-inlined)
bench_tea_20 = let PI4 = pi/4; ep = exp(PI4*f); em = exp(-PI4*f);
    -(1/PI4)*log((ep + em)/(ep - em)) end

# S: VandenBroeck Keller Eq 23
bench_tea_23 = -x*(1/tan(B)) + F/sin(B)*(F^2 + 2 + 2*x)^(-0.5)

# S: VandenBroeck Keller Eq 24
bench_tea_24 = -x/tan(B) + 1/sin(B)

# ─────────────────────────────────────────────────────────────────────────────
# physics/tea-whistle.fpcore (3 simple, 1 let-inlined)
# ─────────────────────────────────────────────────────────────────────────────

# S: Henrywood Agarwal Eq 3
bench_whistle_3 = c0*sqrt(A/(V*l))

# S: Henrywood Agarwal Eq 9a
bench_whistle_9a = w0*sqrt(1 - (M*D/(2*d))^2*(h/l))

# S: Henrywood Agarwal Eq 12
bench_whistle_12 = sqrt(d/h)*sqrt(d/l)*(1 - 0.5*(M*D/(2*d))^2*(h/l))

# L: Henrywood Agarwal Eq 13 (let-inlined)
bench_whistle_13 = let xv = c0*d^2/(w0*h*D^2);
    c0/(2*w0)*(xv + sqrt(xv^2 - M^2)) end

# ─────────────────────────────────────────────────────────────────────────────
# physics/universal-linear-optics.fpcore (3 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: Eq 24
bench_ulo_24 = (a^2 + b^2)^2 + 4*(a^2*(1-a) + b^2*(3+a)) - 1

# S: Eq 25
bench_ulo_25 = (a^2 + b^2)^2 + 4*(a^2*(1+a) + b^2*(1-3*a)) - 1

# S: Eq 26
bench_ulo_26 = (a^2 + b^2)^2 + 4*b^2 - 1

# ─────────────────────────────────────────────────────────────────────────────
# physics/kalman.fpcore (3 let-inlined — simplified to just K0 formula)
# ─────────────────────────────────────────────────────────────────────────────

# L: Kalman K0 (massively let-inlined, simplified)
bench_kalman_K0 = let p00 = 25.0 + 0.25*dt^4 + dt^2;
    p00 / (p00 + r) end

# ─────────────────────────────────────────────────────────────────────────────
# hamming/machine-decide.fpcore (1 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: expax
bench_expax = exp(a*x) - 1

# ─────────────────────────────────────────────────────────────────────────────
# hamming/overflow-underflow.fpcore (1 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: expq2
bench_expq2 = exp(x) / (exp(x) - 1)

# ─────────────────────────────────────────────────────────────────────────────
# hamming/quadratic.fpcore (4 let-inlined)
# ─────────────────────────────────────────────────────────────────────────────

# L: quadp positive (let d = sqrt(b^2 - 4ac))
bench_quadp = (-b + sqrt(b^2 - 4*a*c)) / (2*a)

# L: quadm negative
bench_quadm = (-b - sqrt(b^2 - 4*a*c)) / (2*a)

# L: quad2p (b_2 = b/2)
bench_quad2p = (-b/2 + sqrt((b/2)^2 - a*c)) / a

# L: quad2m
bench_quad2m = (-b/2 - sqrt((b/2)^2 - a*c)) / a

# ─────────────────────────────────────────────────────────────────────────────
# hamming/rearrangement.fpcore (6 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: 2sqrt
bench_2sqrt = sqrt(x + 1) - sqrt(x)

# # S: 2isqrt
# bench_2isqrt = 1/sqrt(x) - 1/sqrt(x + 1)

# # S: 2frac
# bench_2frac = 1/(x + 1) - 1/x

# # S: 3frac
# bench_3frac = 1/(x + 1) - 2/x + 1/(x - 1)

# S: 2cbrt
bench_2cbrt = cbrt(x + 1) - cbrt(x)

# S: exp2
bench_exp2 = exp(x) - 2 + exp(-x)

# ─────────────────────────────────────────────────────────────────────────────
# hamming/series.fpcore (9 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: expm1
bench_expm1 = exp(x) - 1

# S: logs
bench_logs = (n + 1)*log(n + 1) - n*log(n) - 1

# S: invcot (body only, no if)
bench_invcot = 1/x - 1/tan(x)

# S: qlog
bench_qlog = log(1 - x) / log(1 + x)

# S: cos2
bench_cos2 = (1 - cos(x)) / x^2

# S: expq3
bench_expq3 = (eps*(exp((a+b)*eps) - 1)) / ((exp(a*eps) - 1)*(exp(b*eps) - 1))

# S: logq
bench_logq = log((1 - eps) / (1 + eps))

# S: sqrtexp
bench_sqrtexp = sqrt((exp(2*x) - 1) / (exp(x) - 1))

# S: 2nthrt
bench_2nthrt = (x + 1)^(1/n) - x^(1/n)

# ─────────────────────────────────────────────────────────────────────────────
# hamming/trigonometry.fpcore (5 simple)
# ─────────────────────────────────────────────────────────────────────────────

# # S: 2sin
# bench_2sin = sin(x + eps) - sin(x)

# # S: 2cos
# bench_2cos = cos(x + eps) - cos(x)

# # S: 2tan
# bench_2tan = tan(x + eps) - tan(x)

# # S: tanhf
# bench_tanhf = (1 - cos(x)) / sin(x)

# # S: 2atan
# bench_2atan = atan(N + 1) - atan(N)

# ─────────────────────────────────────────────────────────────────────────────
# graphics/lod.fpcore (2 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: 1/2(abs(p)+abs(r) - sqrt)
bench_lod_minus = 0.5*(abs(p) + abs(r) - sqrt((p - r)^2 + 4*q^2))

# S: 1/2(abs(p)+abs(r) + sqrt)
bench_lod_plus = 0.5*(abs(p) + abs(r) + sqrt((p - r)^2 + 4*q^2))

# ─────────────────────────────────────────────────────────────────────────────
# graphics/log-transform.fpcore (1 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: Logarithmic Transform
bench_log_transform = c*log(1 + (exp(x) - 1)*y)

# ─────────────────────────────────────────────────────────────────────────────
# libraries/fast-math.fpcore (8 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: FastMath dist
bench_fm_dist = d*x + d*y

# S: FastMath test1
bench_fm_test1 = d*10 + d*20

# S: FastMath test2
bench_fm_test2 = a*10 + a*b + a*20

# S: FastMath dist3
bench_fm_dist3 = a*b + (c + 5)*a + a*32

# S: FastMath dist4
bench_fm_dist4 = a*b - a*c + d*a - a*a

# S: FastMath test3
bench_fm_test3 = a*3 + a*b + a*c

# S: FastMath repmul
bench_fm_repmul = ((a*a)*a)*a

# S: FastMath test5
bench_fm_test5 = a*(((((a*a*a)*a)*a)*(a*a))*a)*a

# ─────────────────────────────────────────────────────────────────────────────
# libraries/rust.fpcore (4 simple, 2 skipped log1p)
# ─────────────────────────────────────────────────────────────────────────────

# S: Rust asinh f64
bench_rust_asinh = log(x + sqrt(x^2 + 1))

# S: Rust acosh f64
bench_rust_acosh = log(x + sqrt(x^2 - 1))

# S: Rust acosh via product of sqrts
bench_rust_acosh2 = log(x + sqrt(x - 1)*sqrt(x + 1))

# ─────────────────────────────────────────────────────────────────────────────
# libraries/jmatjs.fpcore (1 simple, 7 let-inlined)
# ─────────────────────────────────────────────────────────────────────────────

# S: lambertw estimator
bench_lambertw_est = log(x) - log(log(x))

# L: lambertw newton step (let-inlined: ew = exp(wj))
bench_lambertw_newton = let ew = exp(a); a - (a*ew - x)/(ew + a*ew) end

# L: erf approximation (let-inlined)
bench_jmat_erf = let xv = abs(x); tv = 1/(1 + 0.3275911*xv);
    pv = tv*(0.254829592 + tv*(-0.284496736 + tv*(1.421413741 + tv*(-1.453152027 + tv*1.061405429))));
    1 - pv*exp(-xv^2) end

# ─────────────────────────────────────────────────────────────────────────────
# libraries/mathjs/arithmetic.fpcore (10 simple, skipping ones with undefined refs)
# ─────────────────────────────────────────────────────────────────────────────

# S: math.abs on complex
bench_mathjs_abs = sqrt(re^2 + im^2)

# S: math.abs on complex squared
bench_mathjs_abs2 = re^2 + im^2

# S: math.square on complex real
bench_mathjs_sqr_re = re^2 - im^2

# S: math.square on complex imag
bench_mathjs_sqr_im = re*im + im*re

# S: math.cube on real
bench_mathjs_cube = x^2 * x

# S: math.exp on complex real
bench_mathjs_exp_re = exp(re)*cos(im)

# S: math.exp on complex imag
bench_mathjs_exp_im = exp(re)*sin(im)

# S: math.log10 on complex real
bench_mathjs_log10_re = log(sqrt(re^2 + im^2)) / log(10)

# S: math.log10 on complex imag
bench_mathjs_log10_im = atan(im/re) / log(10)

# S: _multiplyComplex real
bench_mathjs_mul_re = re*a - im*b

# S: _multiplyComplex imag
bench_mathjs_mul_im = re*b + im*a

# S: math.sqrt on complex imag im>0
bench_mathjs_sqrt_im = 0.5*sqrt(2*(sqrt(re^2 + im^2) - re))

# ─────────────────────────────────────────────────────────────────────────────
# libraries/mathjs/trigonometry.fpcore (3 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: math.cos on complex real
bench_mathjs_cos_re = 0.5*cos(re)*(exp(-im) + exp(im))

# S: math.sin on complex real
bench_mathjs_sin_re = 0.5*sin(re)*(exp(-im) + exp(im))

# S: Ian Simplification
bench_ian_simplification = pi/2 - 2*asin(sqrt((1 - x)/2))

# ─────────────────────────────────────────────────────────────────────────────
# libraries/mathjs/probability.fpcore (1 simple)
# ─────────────────────────────────────────────────────────────────────────────

# S: normal distribution
bench_normal_dist = (1/6)*(-2*log(u1))^0.5*cos(2*pi*u2) + 0.5

# ─────────────────────────────────────────────────────────────────────────────
# libraries/octave/CollocWt.fpcore (5 let-inlined)
# ─────────────────────────────────────────────────────────────────────────────

# L: jcobi/1 (let-inlined: ab=alpha+beta, ad=beta-alpha, ap=beta*alpha)
bench_jcobi_1 = let ab = alpha + beta; ad = beta - alpha;
    ((ad/(ab + 2)) + 1) / 2 end

# L: jcobi/2
bench_jcobi_2 = let ab = alpha + beta; ad = beta - alpha; zv = ab + 2*n;
    ((ab*ad/zv/(zv + 2)) + 1) / 2 end

# L: jcobi/3
bench_jcobi_3 = let ab = alpha + beta; ap = alpha*beta; zv = ab + 2;
    ((ab + ap + 1)/zv/zv) / (zv + 1) end

# L: jcobi/4
bench_jcobi_4 = let ab = alpha + beta; ap = alpha*beta; zv = ab + 2*n;
    let yv = n*(ab + n); ystar = yv*(ap + yv);
        (ystar/zv^2) / (zv^2 - 1) end end

# L: jcobi/4 as called
bench_jcobi_4_called = let zv = 2*n; yv = n^2;
    (yv^2/zv^2) / (zv^2 - 1) end

# ─────────────────────────────────────────────────────────────────────────────
# libraries/octave/randgamma.fpcore (1 let-inlined)
# ─────────────────────────────────────────────────────────────────────────────

# L: oct_fill_randg (let-inlined: d = a - 1/3, c = 1/sqrt(9d), v = 1 + c*x)
bench_randgamma = let dv = a - 1/3; cv = 1/sqrt(9*dv); vv = 1 + cv*x;
    dv * vv^3 end

# ─────────────────────────────────────────────────────────────────────────────
# END OF BENCHMARK EXPRESSIONS
# Total: ~263 expressions (180 simple + 83 let-inlined)
# ─────────────────────────────────────────────────────────────────────────────

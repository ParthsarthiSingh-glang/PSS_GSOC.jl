"""
parse_rules.py

Converts Herbie's rules.rkt into egg rewrite! macros

    python parse_rules.py path/to/rules.rkt

most herbie-rules follow this : 

(define-rules group-name
  [rule-name  lhs-pattern  rhs-pattern]
)

"""

import re
import sys

# these rules , i will explore them later , are they actually useful or they cause way too much out of NodeLimit()
SKIP = {
    'pow1',        
    '2-split',     
    '1-split',     
    '1-exp',      
    'e-exp-1',     
    'sinh-0-rev',  
    'cosh-0-rev',  
    'pow-base-0',  
    'add-log-exp', 
}

# MathLang
OPS = {
    '+', '-', '*', '/', 'neg', 'sqrt', 'cbrt', 'pow', 'exp', 'log',
    'sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'atan2',
    'sinh', 'cosh', 'tanh', 'asinh', 'acosh', 'atanh',
    'fabs', 'fmin', 'fmax', 'copysign', 'remainder',
    'erf', 'erfc',
}

CONSTS = {'E', 'PI'}


def is_number(s):
    try:
        float(s)
        return True
    except ValueError:
        pass
    return bool(re.match(r'^-?\d+/\d+$', s))


def is_var(tok):
    if tok in OPS or tok in CONSTS:
        return False
    if is_number(tok):
        return False
    return bool(re.match(r'^[a-zA-Z_][a-zA-Z0-9_-]*$', tok))


def to_egg(expr):
    expr = expr.strip()
    if not expr.startswith('('):
        return f'?{expr}' if is_var(expr) else expr
    inner = expr[1:-1].strip()
    toks = to_token(inner)
    if not toks:
        return expr
    op, args = toks[0], toks[1:]
    if op in CONSTS and not args:
        return op
    return f'({op} {" ".join(to_egg(a) for a in args)})'


def to_token(s):
    """SIMILAR TO TOKENIZE in our expression building"""
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c in ' \t\n':
            i += 1
        elif c == '(':
            depth, j = 1, i + 1
            while j < len(s) and depth:
                depth += (s[j] == '(') - (s[j] == ')')
                j += 1
            out.append(s[i:j])
            i = j
        else:
            j = i
            while j < len(s) and s[j] not in ' \t\n()':
                j += 1
            out.append(s[i:j])
            i = j
    return out


def _split_lhs_rhs(s):
    """Split a rule body into exactly two top-level s-expressions."""
    parts, depth, start, i = [], 0, 0, 0
    while i < len(s):
        c = s[i]
        if c == '(':
            if depth == 0:
                start = i
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                parts.append(s[start:i + 1])
        elif depth == 0 and c not in ' \t\n':
            j = i
            while j < len(s) and s[j] not in ' \t\n()':
                j += 1
            parts.append(s[i:j])
            i = j
            continue
        i += 1
    return parts if len(parts) == 2 else []


def parse(path):
    with open(path, encoding='utf-8') as f:
        src = f.read()

    # Drop unsound rules (lines beginning with #;)
    src = re.sub(r'#;[^\[]*\[[^\]]*\]', '', src, flags=re.DOTALL)

    block_re = re.compile(
        r'\(define-rules\s+(\S+)\s*((?:\s*\[[^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)*\]\s*)+)\)',
        re.DOTALL,
    )
    rule_re = re.compile(r'\[(\S+)\s+(.*?)\](?=\s*(?:\[|\)))', re.DOTALL)

    results, seen = [], set()

    for block in block_re.finditer(src):
        group, body = block.group(1), block.group(2)
        for m in rule_re.finditer(body):
            name, raw = m.group(1), m.group(2).strip()
            if name in SKIP or name in seen:
                continue
            if any(g in raw for g in ('sound-/', 'sound-pow', 'sound-log')):
                continue
            pair = _split_lhs_rhs(raw)
            if not pair:
                continue
            seen.add(name)
            results.append((group, name, to_egg(pair[0]), to_egg(pair[1])))

    return results


if __name__ == '__main__':
    path = sys.argv[1] if len(sys.argv) > 1 else 'rules.rkt'
    rules = parse(path)

    cur = None
    for group, name, lhs, rhs in rules:
        if group != cur:
            print(f'\n// {group}')
            cur = group
        print(f'rewrite!("{name}"; "{lhs}" => "{rhs}"),')

    print(f'\n// total: {len(rules)} rules', file=sys.stderr)

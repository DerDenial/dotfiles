.pragma library

// A bounded arithmetic grammar. Input is never JavaScript or a shell command.
var MAX_LENGTH = 512;
var MAX_TOKENS = 256;
var MAX_DEPTH = 32;
var MAX_OPERATIONS = 256;
var FUNCTIONS = ["sqrt", "abs", "round", "floor", "ceil", "sin", "cos", "tan", "log", "ln"];
var SUPERSCRIPT_DIGITS = "⁰¹²³⁴⁵⁶⁷⁸⁹";

function failure(message, nonMath) {
    return { calculatorError: true, message: message, nonMath: nonMath === true };
}

function tokenize(expression) {
    var tokens = [];
    var offset = 0;
    while (offset < expression.length) {
        var character = expression.charAt(offset);
        if (/\s/.test(character)) { ++offset; continue; }
        if (tokens.length >= MAX_TOKENS) throw failure("This calculation is too complex.");
        var rest = expression.slice(offset);
        if (/[0-9.]/.test(character)) {
            var number = /^(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/.exec(rest);
            if (!number) throw failure("Enter a valid number.", character === "." && /[a-zA-Z_]/.test(rest.charAt(1)));
            var value = Number(number[0]);
            if (!Number.isFinite(value)) throw failure("This number is too large.");
            tokens.push({ type: "number", value: value });
            offset += number[0].length;
        } else if (/[⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻]/.test(character)) {
            var superscript = /^[⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻]+/.exec(rest)[0];
            if (!/^[⁺⁻]?[⁰¹²³⁴⁵⁶⁷⁸⁹]+$/.test(superscript))
                throw failure("Use one optional sign followed by exponent digits.");
            var exponent = "";
            for (var i = 0; i < superscript.length; ++i) {
                var digit = superscript.charAt(i);
                exponent += digit === "⁻" ? "-" : digit === "⁺" ? "+" : String(SUPERSCRIPT_DIGITS.indexOf(digit));
            }
            var exponentValue = Number(exponent);
            if (!Number.isSafeInteger(exponentValue)) throw failure("This exponent is too large.");
            tokens.push({ type: "superscript", value: exponentValue });
            offset += superscript.length;
        } else if (/[a-zA-Z_]/.test(character)) {
            var identifier = /^[a-zA-Z_]+/.exec(rest)[0].toLowerCase();
            if (identifier !== "pi" && identifier !== "e" && FUNCTIONS.indexOf(identifier) < 0)
                throw failure("Use numbers and supported calculator functions.", true);
            tokens.push({ type: "name", value: identifier });
            offset += identifier.length;
        } else if ("+-*/^()%".indexOf(character) >= 0) {
            if (character === "*" && expression.charAt(offset + 1) === "*") {
                tokens.push({ type: "^" }); offset += 2;
            } else {
                tokens.push({ type: character }); ++offset;
            }
        } else {
            throw failure("Use numbers, operators and parentheses.", true);
        }
    }
    return tokens;
}

function automaticIntent(expression, tokens) {
    // Dates, app names, filenames and lone numbers remain ordinary searches.
    if (/^\d{4}[-/]\d{1,2}[-/]\d{1,2}$/.test(expression)
        || /^\d{1,2}[-/]\d{1,2}[-/]\d{4}$/.test(expression)) return false;
    if (!tokens.length) return false;
    var first = tokens[0];
    if (first.type !== "number" && first.type !== "name" && first.type !== "("
        && first.type !== "+" && first.type !== "-") return false;
    if (/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(expression)) return false;
    return tokens.some(function(token) {
        return token.type === "+" || token.type === "-" || token.type === "*" || token.type === "/"
            || token.type === "^" || token.type === "%" || token.type === "(" || token.type === ")"
            || token.type === "superscript";
    });
}

function mathPrefix(expression) {
    return /^(?:[+-]?\s*(?:\d|\.)|\(|(?:sqrt|abs|round|floor|ceil|sin|cos|tan|log|ln|pi|e)\b)/i.test(expression)
        && /[+*/^%()\-⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻]/.test(expression);
}

function calculate(tokens) {
    var position = 0;
    var depth = 0;
    var operations = 0;

    function enter() {
        if (++depth > MAX_DEPTH) throw failure("This calculation is nested too deeply.");
    }
    function leave(value) { --depth; return value; }
    function type() { return position < tokens.length ? tokens[position].type : "end"; }
    function take(expected) {
        if (type() !== expected) return false;
        ++position; return true;
    }
    function checked(value) {
        if (++operations > MAX_OPERATIONS) throw failure("This calculation is too complex.");
        if (!Number.isFinite(value)) throw failure("The result is outside the supported number range.");
        return value;
    }
    function sum() {
        var value = product();
        while (type() === "+" || type() === "-") {
            var operation = tokens[position++].type;
            var right = product();
            value = checked(operation === "+" ? value + right : value - right);
        }
        return value;
    }
    function product() {
        var value = unary();
        while (type() === "*" || type() === "/") {
            var operation = tokens[position++].type;
            var right = unary();
            if (operation === "/" && right === 0) throw failure("Cannot divide by zero.");
            value = checked(operation === "*" ? value * right : value / right);
        }
        return value;
    }
    function unary() {
        enter();
        var value;
        if (take("+")) value = unary();
        else if (take("-")) value = checked(-unary());
        else value = power();
        return leave(value);
    }
    function power() {
        var value = postfix();
        // The right side includes unary operators: 2^-2, -2^2 and 2^3^2
        // follow ordinary mathematical precedence without JavaScript's XOR.
        if (take("^")) value = checked(Math.pow(value, unary()));
        return value;
    }
    function postfix() {
        var value = primary();
        var previousSuperscript = false;
        while (type() === "%" || type() === "superscript") {
            if (take("%")) {
                value = checked(value / 100);
                previousSuperscript = false;
            } else {
                if (previousSuperscript) throw failure("Keep the exponent digits together, or add parentheses.");
                // Superscripts bind to the preceding value, including its full
                // multi-digit exponent. This also keeps 2²% equal to (2²)%.
                value = checked(Math.pow(value, tokens[position++].value));
                previousSuperscript = true;
            }
        }
        return value;
    }
    function primary() {
        if (take("(")) {
            var nested = sum();
            if (!take(")")) throw failure("Close the parenthesis to finish this calculation.");
            return nested;
        }
        if (type() === "number") return tokens[position++].value;
        if (type() === "name") {
            var name = tokens[position++].value;
            if (name === "pi") return Math.PI;
            if (name === "e") return Math.E;
            if (!take("(")) throw failure("Put the function's number in parentheses.");
            var argument = sum();
            if (!take(")")) throw failure("Close the parenthesis to finish this calculation.");
            return checked(applyFunction(name, argument));
        }
        if (type() === "end") throw failure("Complete the calculation to see the result.");
        throw failure("Check the operators and parentheses.");
    }

    var value = sum();
    if (position !== tokens.length) throw failure("Add an operator between numbers or parentheses.");
    return value;
}

function applyFunction(name, value) {
    if (name === "sqrt") {
        if (value < 0) throw failure("Square root needs a non-negative number.");
        return Math.sqrt(value);
    }
    if (name === "abs") return Math.abs(value);
    if (name === "round") return value < 0 ? -Math.round(-value) : Math.round(value);
    if (name === "floor") return Math.floor(value);
    if (name === "ceil") return Math.ceil(value);
    if (name === "log" || name === "ln") {
        if (value <= 0) throw failure("Logarithms need a positive number.");
        return name === "ln" ? Math.log(value) : Math.log(value) / Math.LN10;
    }
    if (name === "tan" && Math.abs(Math.cos(value)) < 1e-14)
        throw failure("Tangent is undefined at this angle.");
    var result = name === "sin" ? Math.sin(value) : name === "cos" ? Math.cos(value) : Math.tan(value);
    // Constants such as pi are finite approximations; avoid a visible floating
    // point tail for sin(pi) and cos(pi/2) without rounding tiny input numbers.
    if (Math.abs(result) < 1e-15 && Math.abs(value) > 1e-12) return 0;
    if (Math.abs(result - 1) < 1e-15) return 1;
    if (Math.abs(result + 1) < 1e-15) return -1;
    return result;
}

function format(value) {
    if (!Number.isFinite(value)) return "";
    if (value === 0) return "0";
    if (Number.isSafeInteger(value)) return String(value);
    // Fourteen significant digits remove arithmetic display noise, e.g.
    // 0.1+0.2, while preserving a useful range for scientific notation.
    return String(Number(value.toPrecision(14)));
}

function evaluate(input) {
    if (typeof input !== "string") return { intent: false, ok: false, text: "", expression: "" };
    var bounded = input.slice(0, MAX_LENGTH + 1).trim();
    var explicit = bounded.charAt(0) === "=";
    var expression = (explicit ? bounded.slice(1) : bounded).trim()
        .replace(/\u00d7/g, "*").replace(/\u00f7/g, "/").replace(/\u2212/g, "-").replace(/,/g, ".");
    if (input.length > MAX_LENGTH) {
        return { intent: explicit || mathPrefix(expression), ok: false, text: "", expression: expression.slice(0, MAX_LENGTH), error: "This calculation is too long." };
    }
    if (!expression) return { intent: explicit, ok: false, text: "", expression: "", error: "Enter a calculation." };
    var intent = explicit || mathPrefix(expression);
    try {
        var tokens = tokenize(expression);
        intent = explicit || automaticIntent(expression, tokens);
        if (!intent) return { intent: false, ok: false, text: "", expression: expression };
        var value = calculate(tokens);
        return { intent: true, ok: true, text: format(value), value: value, expression: expression };
    } catch (error) {
        // Lexical failures still belong to explicit calculator input. Normal
        // non-math queries, including app/file names, keep their search behavior.
        if (!explicit && error.nonMath) intent = false;
        return { intent: intent, ok: false, text: "", expression: expression,
            error: error.calculatorError ? error.message : "Could not calculate this expression." };
    }
}

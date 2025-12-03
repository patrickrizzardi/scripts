import path from "path";
import { fileURLToPath } from "url";

import { fixupPluginRules } from "@eslint/compat";
import eslint from "@eslint/js";
import _import from "eslint-plugin-import";
import globals from "globals";
import { configs, parser, plugin } from "typescript-eslint";

// Get the directory name using ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Parser for TypeScript code
const tsParser = parser;

// TypeScript ESLint plugin
const typescriptEslintPlugin = plugin;

/** Rule categories */
const appRules = {
  /** Possible Problems: Catch potential runtime errors or bugs */
  possibleProblems: {
    // Prevents runtime errors from missing array method returns (e.g., map, filter)
    "array-callback-return": "error",
    // Catches logical errors in binary expressions that always evaluate to true/false
    "no-constant-binary-expression": "error",
    // Prevents invalid returns in constructors, avoiding runtime errors
    "no-constructor-return": "error",
    // Blocks misuse of built-in types like Symbol as constructors
    "no-new-native-nonconstructor": "error",
    // Prevents Promise executor functions from returning values, avoiding unexpected behavior
    "no-promise-executor-return": "error",
    // Catches redundant self-comparisons (e.g., x === x) that indicate logic errors
    "no-self-compare": "error",
    // Prevents confusing template literal syntax in regular strings
    "no-template-curly-in-string": "error",
    // Detects infinite loops due to unchanged conditions
    "no-unmodified-loop-condition": "error",
    // Identifies loops that execute at most once, indicating potential bugs
    "no-unreachable-loop": "error",
    // Ensures private class members are used, avoiding dead code
    "no-unused-private-class-members": "error",
    /** Prevents race conditions in async code by ensuring atomic updates (require-atomic-updates) */
    "require-atomic-updates": "error",
    // Prevents duplicate enum values, avoiding runtime confusion
    "@typescript-eslint/no-duplicate-enum-values": "error",
    // Catches duplicate types in unions/intersections, preventing type errors
    "@typescript-eslint/no-duplicate-type-constituents": "error",
    // Disallows empty classes that add no functionality, reducing code clutter
    "@typescript-eslint/no-extraneous-class": "error",
    // Prevents for-in loops on arrays, which can cause incorrect iteration
    "@typescript-eslint/no-for-in-array": "error",
    // Prevents non-null assertions in nullish coalescing, avoiding runtime errors
    "@typescript-eslint/no-non-null-asserted-nullish-coalescing": "error",
    // Blocks non-null assertions with optional chaining, preventing invalid access
    "@typescript-eslint/no-non-null-asserted-optional-chain": "error",
    /** Prevents non-null assertions to avoid runtime errors from null/undefined access (@typescript-eslint/no-non-null-assertion) */
    "@typescript-eslint/no-non-null-assertion": "error",
    // Disallows comparing enums with incompatible types, preventing logic errors
    "@typescript-eslint/no-unsafe-enum-comparison": "error",
    // Disabled as covered by TypeScript or overlapping
    // TSC catches duplicate class members with strict:true
    "@typescript-eslint/no-dupe-class-members": "off",
    // Slow rule, TSC catches redeclarations with strict:true
    "@typescript-eslint/no-redeclare": "off",
    // Slow rule, TSC catches this with strict:true, overlaps with no-var
    "block-scoped-var": "off",
    // Slow rule, TSC catches this with strict:true
    "@typescript-eslint/no-misused-new": "off",
  },

  /** Best Practices: Enforce coding conventions and best practices */
  bestPractices: {
    // Encourages concise arrow function bodies for better readability
    "arrow-body-style": ["error", "as-needed"],
    // Enforces camelCase naming for variables and properties for consistency
    camelcase: ["error"],
    /** Limits function complexity to improve maintainability (complexity) */
    complexity: ["error", 20],
    // Requires curly braces for multi-line blocks to prevent errors from code changes
    curly: ["error", "multi-line"],
    // Ensures switch statements have a default case for robustness
    "default-case": "error",
    // Requires default case to be last in switch for logical flow
    "default-case-last": "error",
    // Enforces strict equality (===) to avoid type coercion bugs
    eqeqeq: "error",
    // Ensures function names match assigned variables for clarity
    "func-name-matching": "error",
    // Prefers function expressions for consistency in functional programming
    "func-style": ["error", "expression"],
    // Requires guarding for-in loops to avoid iterating over inherited properties
    "guard-for-in": "error",
    // Promotes logical assignment operators for concise code
    "logical-assignment-operators": "error",
    // Limits files to one class for better modularity
    "max-classes-per-file": ["error", 1],
    /** Limits block nesting to 6 levels to improve code readability (max-depth) */
    "max-depth": ["error", 6],
    /** Caps file length at 300 lines to encourage modular code (max-lines) */
    "max-lines": ["error", 300],
    /** Restricts function length to 75 lines (excluding comments) for maintainability (max-lines-per-function) */
    "max-lines-per-function": [
      "error",
      { max: 125, skipBlankLines: true, skipComments: true },
    ],
    // Limits nested callbacks to 4 for simpler asynchronous code
    "max-nested-callbacks": ["error", 4],
    // Caps function parameters at 4 to reduce complexity
    "max-params": ["error", 4],
    // Limits statements per function to 30 for clarity
    "max-statements": ["error", 30],
    /** Enforces capitalized constructor names with exceptions for specific classes (new-cap) */
    "new-cap": [
      "error",
      {
        capIsNewExceptions: [
          "Attribute",
          "Table",
          "Default",
          "HasOne",
          "HasMany",
          "BelongsTo",
          "ENUM",
          "BelongsToMany",
        ],
      },
    ],
    // Disallows window.alert for better user experience
    "no-alert": "error",
    // Prevents bitwise operators to avoid confusing logic
    "no-bitwise": "error",
    // Avoids ambiguous arrow functions in conditionals for clarity
    "no-confusing-arrow": "error",
    // Disallows console.log to prevent debugging code in production
    "no-console": "error",
    // Eliminates unnecessary else clauses after return for cleaner code
    "no-else-return": "error",
    // Prevents empty blocks that may indicate incomplete code
    "no-empty": "error",
    // Disallows empty static blocks to avoid dead code
    "no-empty-static-block": "error",
    // Prevents loose equality with null to avoid coercion issues
    "no-eq-null": "error",
    // Blocks eval() usage to prevent security and performance issues
    "no-eval": "error",
    // Disallows extending native objects to maintain standard behavior
    "no-extend-native": "error",
    // Prevents unnecessary function binding for performance
    "no-extra-bind": "error",
    // Eliminates unused labels to avoid confusion
    "no-extra-label": "error",
    // Requires explicit decimals (e.g., 0.5) for clarity
    "no-floating-decimal": "error",
    // Prevents implicit type coercion for predictable behavior
    "no-implicit-coercion": [
      "error",
      { boolean: true, number: true, string: true },
    ],
    // Prevents labeled statements to simplify control flow
    "no-labels": "error",
    // Eliminates unnecessary block statements
    "no-lone-blocks": "error",
    // Avoids single if statements in else blocks for cleaner code
    "no-lonely-if": "error",
    // Disallows multiple assignments in one line for clarity
    "no-multi-assign": "error",
    // Prevents multiline strings for better readability
    "no-multi-str": "error",
    // Avoids negated conditions in if statements for clarity
    "no-negated-condition": "error",
    // Disallows nested ternary operators to prevent complex logic
    "no-nested-ternary": "error",
    // Prevents new without assignment to avoid side-effect-only calls
    "no-new": "error",
    // Blocks Function constructor for security and clarity
    "no-new-func": "error",
    /** Prevents parameter reassignment to avoid unintended side effects (no-param-reassign) */
    "no-param-reassign": "error",
    // Disallows assignments in return statements unless parenthesized
    "no-return-assign": ["error", "except-parens"],
    // Blocks javascript: URLs for security
    "no-script-url": "error",
    // Eliminates unnecessary ternary expressions
    "no-unneeded-ternary": "error",
    // Prevents unnecessary function calls for performance
    "no-useless-call": "error",
    // Eliminates redundant return statements
    "no-useless-return": "error",
    // Enforces let/const over var for better scoping
    "no-var": "error",
    // Prevents unnecessary escape characters in strings
    "no-useless-escape": "error",
    // Encourages shorthand syntax for object literals
    "object-shorthand": "error",
    // Requires single variable declarations for clarity
    "one-var": ["error", "never"],
    // Promotes operator assignment (e.g., +=) for concise code
    "operator-assignment": "error",
    // Prefers arrow functions for callbacks for consistency
    "prefer-arrow-callback": "error",
    // Encourages const for variables that aren’t reassigned
    "prefer-const": "error",
    // Promotes destructuring for cleaner object/array access
    "prefer-destructuring": "error",
    // Requires named capture groups in regex for clarity
    "prefer-named-capture-group": "error",
    // Promotes object spread over Object.assign
    "prefer-object-spread": "error",
    // Requires Promise.reject with Error objects for better debugging
    "prefer-promise-reject-errors": "error",
    // Promotes rest parameters over arguments object
    "prefer-rest-params": "error",
    // Encourages spread operator over apply for clarity
    "prefer-spread": "error",
    // Promotes template literals over string concatenation
    "prefer-template": "error",
    // Requires radix parameter in parseInt for explicit base
    radix: "error",
    // Enforces sorted variable declarations for consistency
    "sort-vars": "error",
    // Requires variables to be declared at the top of scope
    "vars-on-top": "error",
    // Prevents Yoda conditions for natural reading order
    yoda: ["error", "never", { exceptRange: true }],
    // Prevents empty interfaces, encouraging meaningful types
    "@typescript-eslint/no-empty-interface": "error",
    /** Allows any type with specific handling to avoid unsafe usage (no-explicit-any) */
    "@typescript-eslint/no-explicit-any": [
      "off",
      { ignoreRestArgs: true, fixToUnknown: true },
    ],
    // Prevents redundant non-null assertions
    "@typescript-eslint/no-extra-non-null-assertion": "error",
    // Enforces import over require() for ES module consistency
    "@typescript-eslint/no-require-imports": "error",
    // Prevents aliasing `this` to avoid confusion
    "@typescript-eslint/no-this-alias": "error",
    // Enforces import over require() for ES module consistency
    "@typescript-eslint/no-var-requires": "error",
    // Enforces initializers for enum members for clarity
    "@typescript-eslint/prefer-enum-initializers": "error",
    // Promotes for-of loops over forEach for performance
    "@typescript-eslint/prefer-for-of": "error",
    // Encourages function types over interfaces for simplicity
    "@typescript-eslint/prefer-function-type": "error",
    // Promotes includes() over indexOf for readable code
    "@typescript-eslint/prefer-includes": "error",
    // Requires literal enum members for predictable values
    "@typescript-eslint/prefer-literal-enum-member": "error",
    // Promotes namespace keyword over module for clarity
    "@typescript-eslint/prefer-namespace-keyword": "error",
    // Encourages readonly properties for immutability
    "@typescript-eslint/prefer-readonly": "error",
    // Promotes reduce with explicit type parameters
    "@typescript-eslint/prefer-reduce-type-parameter": "error",
    // Encourages RegExp.exec over match for performance
    "@typescript-eslint/prefer-regexp-exec": "error",
    // Promotes startsWith/endsWith over substring checks
    "@typescript-eslint/prefer-string-starts-ends-with": "error",
    // Enforces @ts-expect-error over @ts-ignore for clarity
    "@typescript-eslint/prefer-ts-expect-error": "error",
    // Requires array sort to use compare functions
    "@typescript-eslint/require-array-sort-compare": "error",
    // Ensures default parameters are last in function signatures
    "@typescript-eslint/default-param-last": "error",
    // Promotes dot notation over bracket notation for properties
    "@typescript-eslint/dot-notation": "error",
    // Requires variable initialization for clarity
    "@typescript-eslint/init-declarations": "error",
    // Disallows Array constructor in favor of array literals
    "@typescript-eslint/no-array-constructor": "error",
    // Prevents empty functions to avoid dead code
    "@typescript-eslint/no-empty-function": "error",
    // Blocks implied eval (e.g., setTimeout(string)) for security
    "@typescript-eslint/no-implied-eval": "error",
    // Ensures correct usage of `this` in methods
    "@typescript-eslint/no-invalid-this": "error",
    // Prevents function declarations in loops to avoid closures
    "@typescript-eslint/no-loop-func": "error",
    // Catches loss of numeric precision in literals
    "@typescript-eslint/no-loss-of-precision": "error",
    // Prevents variable shadowing for clarity
    "@typescript-eslint/no-shadow": "error",
    // Disallows unused expressions to catch potential errors
    "@typescript-eslint/no-unused-expressions": "error",
    /** Prevents unused variables, with allowances for underscored names (@typescript-eslint/no-unused-vars) */
    "@typescript-eslint/no-unused-vars": [
      "error",
      {
        argsIgnorePattern: "^_",
        varsIgnorePattern: "^_",
        caughtErrorsIgnorePattern: "^_",
      },
    ],
    // Eliminates unnecessary constructors for cleaner code
    "@typescript-eslint/no-useless-constructor": "error",
    // Disabled as covered by TypeScript or overlapping
    // TSC catches default parameters with strict:true
    "default-param-last": "off",
    // TSC catches dot notation issues with strict:true
    "dot-notation": "off",
    // TSC catches uninitialized variables with strict:true
    "init-declarations": "off",
    // TSC catches Array constructor issues with strict:true
    "no-array-constructor": "off",
    // TSC catches empty functions with strict:true
    "no-empty-function": "off",
    // TSC catches implied eval with strict:true
    "no-implied-eval": "off",
    // TSC catches invalid `this` usage with strict:true
    "no-invalid-this": "off",
    // TSC catches functions in loops with strict:true
    "no-loop-func": "off",
    // TSC catches precision loss with strict:true
    "no-loss-of-precision": "off",
    // TSC catches shadowed variables with strict:true
    "no-shadow": "off",
    // TSC catches unused expressions with strict:true
    "no-unused-expressions": "off",
    // TSC catches unused variables with strict:true
    "no-unused-vars": "off",
    // TSC catches unnecessary constructors with strict:true
    "no-useless-constructor": "off",
    // TSC catches this with strict:true, overlaps with no-unused-vars
    "no-implicit-globals": "off",
    // TSC catches this with strict:true, overlaps with no-array-constructor
    "no-new-object": "off",
    // Overlaps with prefer-template
    "no-useless-concat": "off",
    // TSC catches this with strict:true, overlaps with restrict-template-expressions
    "no-useless-computed-key": "off",
    // Optional, not critical
    "prefer-numeric-literals": "off",
    // Slow rule, TSC catches this with strict:true
    "@typescript-eslint/no-unnecessary-boolean-literal-compare": "off",
    // Slow rule, TSC catches this with strict:true
    "@typescript-eslint/no-unnecessary-type-arguments": "off",
    // Slow rule, TSC catches this with strict:true
    "@typescript-eslint/no-unnecessary-type-constraint": "off",
  },

  /** Formatting: Enforce code style and formatting (handled by Prettier where possible) */
  formatting: {
    /** Enforces consistent naming conventions for variables, types, and enums for code clarity (@typescript-eslint/naming-convention) */
    "@typescript-eslint/naming-convention": [
      "error",
      {
        selector: "variable",
        format: ["camelCase", "PascalCase", "UPPER_CASE"],
        leadingUnderscore: "allow",
      },
      {
        selector: ["parameter", "typeProperty"],
        format: ["camelCase", "PascalCase"],
        leadingUnderscore: "allow",
      },
      {
        selector: ["interface", "typeParameter", "enum"],
        format: ["PascalCase"],
      },
    ],
    // Disabled as handled by Prettier
    // Handled by Prettier (bracketSpacing: true)
    "array-bracket-spacing": "off",
    // Handled by Prettier (trailingComma: all)
    "comma-dangle": "off",
    // Handled by Prettier (semi: true)
    "semi-spacing": "off",
    // Handled by Prettier
    "space-before-blocks": "off",
    // Handled by Prettier (arrowParens: always)
    "space-before-function-paren": "off",
    // Handled by Prettier
    "space-infix-ops": "off",
    // Handled by Prettier
    "space-unary-ops": "off",
    // Handled by Prettier
    "template-curly-spacing": "off",
    // Handled by Prettier
    "spaced-comment": "off",
    // Handled by Prettier
    "sort-imports": "off",
    // Disabled as stylistic or covered by TypeScript
    // TSC catches extra semicolons with strict:true
    "no-extra-semi": "off",
    // Stylistic, optional
    "no-mixed-operators": "off",
    // Stylistic, optional
    "no-inline-comments": "off",
    // Stylistic, optional
    "require-unicode-regexp": "off",
  },

  /** Imports: Enforce best practices for ES module imports */
  imports: {
    // Ensures valid export statements
    "import/export": "error",
    // Disallows mutable exports to avoid side effects
    "import/no-mutable-exports": "error",
    // Prevents absolute import paths for consistency
    "import/no-absolute-path": "error",
    // Blocks dynamic require() calls for ES module compatibility
    "import/no-dynamic-require": "error",
    // Ensures consistent type import syntax
    "import/consistent-type-specifier-style": "error",
    // Ensures imports are at the top of the file
    "import/first": "error",
    // Requires newline after imports for readability
    "import/newline-after-import": "error",
    // Prevents duplicate imports for cleaner code
    "import/no-duplicates": "error",
    /** Enforces sorted import statements for maintainability (import/order) */
    "import/order": "error",
    // Disabled as covered by TypeScript or overlapping
    // TSC catches invalid default imports with strict:true
    "import/default": "off",
    // TSC catches invalid named imports with strict:true
    "import/named": "off",
    // Slow rule, TSC catches invalid namespace imports with strict:true
    "import/namespace": "off",
    // Slow rule, optional
    "import/no-deprecated": "off",
    // TSC catches extension issues with strict:true
    "import/extensions": "off",
    // TSC catches unresolved imports with strict:true
    "import/no-unresolved": "off",
    // Stylistic, optional
    "import/group-exports": "off",
    // Slow rule, TSC catches invalid default-as-named imports with strict:true
    "import/no-named-as-default-member": "off",
    // Optional, not critical
    "import/no-useless-path-segments": "off",
    // Optional, not critical, overlaps with no-unused-vars
    "import/no-unused-modules": "off",
    // Optional, not critical
    "import/no-empty-named-blocks": "off",
    // Optional, not critical
    "import/no-amd": "off",
    // Optional, not critical
    "import/no-commonjs": "off",
  },

  /** Type Safety: TypeScript-specific rules for type-related errors */
  typeSafety: {
    // Ensures adjacent overload signatures for better readability
    "@typescript-eslint/adjacent-overload-signatures": "error",
    // Enforces consistent array type syntax (e.g., Array<T> vs T[])
    "@typescript-eslint/array-type": ["error", { default: "generic" }],
    // Promotes consistent property style in classes
    "@typescript-eslint/class-literal-property-style": "error",
    // Ensures consistent generic constructor syntax
    "@typescript-eslint/consistent-generic-constructors": "error",
    // Prefers Record over object for indexed types
    "@typescript-eslint/consistent-indexed-object-style": ["error", "record"],
    // Enforces consistent type assertions (e.g., `as` over casting)
    "@typescript-eslint/consistent-type-assertions": [
      "error",
      { assertionStyle: "as" },
    ],
    // Prefers interface over type for object types
    "@typescript-eslint/consistent-type-definitions": ["error", "interface"],
    // Ensures consistent type exports for clarity
    "@typescript-eslint/consistent-type-exports": [
      "error",
      { fixMixedExportsWithInlineTypeSpecifier: true },
    ],
    // Requires explicit function return types for type safety
    "@typescript-eslint/explicit-function-return-type": "error",
    /** Requires explicit accessibility modifiers (e.g., private) for class members (@typescript-eslint/explicit-member-accessibility) */
    "@typescript-eslint/explicit-member-accessibility": [
      "error",
      { accessibility: "no-public" },
    ],
    // Enforces consistent type imports (e.g., `import type`)
    "@typescript-eslint/consistent-type-imports": [
      "error",
      {
        prefer: "type-imports",
        disallowTypeAnnotations: true,
        fixStyle: "separate-type-imports",
      },
    ],
    // Requires explicit return types for module boundaries
    "@typescript-eslint/explicit-module-boundary-types": "error",
    // Prefers property signatures over method signatures in interfaces
    "@typescript-eslint/method-signature-style": ["error", "property"],
    // Prevents toString() calls on objects without proper stringification
    "@typescript-eslint/no-base-to-string": "error",
    // Avoids confusing non-null assertions in complex expressions
    "@typescript-eslint/no-confusing-non-null-assertion": "error",
    // Prevents mixing different enum types
    "@typescript-eslint/no-mixed-enums": "error",
    // Disallows namespace declarations for modern module syntax
    "@typescript-eslint/no-namespace": "error",
    // Enforces non-nullable type assertion style
    "@typescript-eslint/non-nullable-type-assertion-style": "error",
    // Ensures plus operands are compatible types
    "@typescript-eslint/restrict-plus-operands": "error",
    /** Restricts template literal expressions to safe types for runtime safety (@typescript-eslint/restrict-template-expressions) */
    "@typescript-eslint/restrict-template-expressions": "error",
    // Enforces sorted type constituents for clarity
    "@typescript-eslint/sort-type-constituents": "error",
    // Requires exhaustive switch cases for enums/unions
    "@typescript-eslint/switch-exhaustiveness-check": "error",
    // Promotes unified function signatures for overloading
    "@typescript-eslint/unified-signatures": "error",
    // Restricts imports to specific patterns
    "@typescript-eslint/no-restricted-imports": "error",
    // Disabled as covered by TypeScript
    // Slow rule, TSC catches unnecessary conditions with strict:true
    "@typescript-eslint/no-unnecessary-condition": "off",
    // Slow rule, TSC catches unnecessary type assertions with strict:true
    "@typescript-eslint/no-unnecessary-type-assertion": "off",
    // Slow rule, TSC catches unsafe assignments with strict:true
    "@typescript-eslint/no-unsafe-assignment": "off",
    // Slow rule, TSC catches unsafe arguments with strict:true
    "@typescript-eslint/no-unsafe-argument": "off",
    // Slow rule, TSC catches unsafe returns with strict:true
    "@typescript-eslint/no-unsafe-return": "off",
    // Slow rule, TSC catches confusing void expressions with strict:true
    "@typescript-eslint/no-confusing-void-expression": "off",
    // Slow rule, TSC catches invalid await usage with strict:true
    "@typescript-eslint/await-thenable": "off",
    // Optional, not critical
    "@typescript-eslint/no-dynamic-delete": "off",
    // Optional, not critical
    "@typescript-eslint/no-invalid-void-type": "off",
    // Optional, not critical
    "@typescript-eslint/no-use-before-define": "off",
  },

  /** Async/Promises: TypeScript rules for async and promise handling */
  asyncPromises: {
    /** Prevents unhandled promise rejections that could crash async operations like webhook handlers (@typescript-eslint/no-floating-promises) */
    "@typescript-eslint/no-floating-promises": ["error", { ignoreVoid: false }],
    /** Catches incorrect promise usage, such as async functions in non-async callbacks, critical for async-heavy code (@typescript-eslint/no-misused-promises) */
    "@typescript-eslint/no-misused-promises": "error",
    // Ensures async functions return promises for consistency
    "@typescript-eslint/promise-function-async": "error",
    /** Ensures async functions contain await or return a Promise to avoid unnecessary async keywords (@typescript-eslint/require-await) */
    "@typescript-eslint/require-await": "error",
    // Enforces consistent return await usage for error handling
    "@typescript-eslint/return-await": "error",
    // Replaced by @typescript-eslint/require-await
    "require-await": "off",
    // Replaced by @typescript-eslint/return-await
    "no-return-await": "off",
  },
};

/** Test-specific rules: Relaxed for test files */
const testRules = {
  // Allows empty arrow functions in test mocks
  "no-empty-function": "off",
  // Allows empty functions in test code
  "@typescript-eslint/no-empty-function": "off",
  // Permits non-concise arrow function bodies in tests
  "arrow-body-style": "off",
  // Allows unused variables in test code
  "@typescript-eslint/no-unused-vars": "off",
  // Permits any return types in test assertions
  "@typescript-eslint/no-unsafe-return": "off",
  // Allows any type in test code for flexibility
  "@typescript-eslint/no-explicit-any": "off",
  // Allows longer functions in test files
  "max-lines-per-function": "off",
  // Permits larger test files
  "max-lines": "off",
  // Allows more statements in test functions
  "max-statements": "off",
  // Permits more parameters in test functions
  "max-params": "off",
  // Allows deeper callback nesting in tests
  "max-nested-callbacks": "off",
  // Permits unsafe assignments in test assertions
  "@typescript-eslint/no-unsafe-assignment": "off",
  // Allows unsafe member access in test code
  "@typescript-eslint/no-unsafe-member-access": "off",
  // Permits unsafe function calls in tests
  "@typescript-eslint/no-unsafe-call": "off",
  // Allows unsafe arguments in test code
  "@typescript-eslint/no-unsafe-argument": "off",
  // Permits unbound methods in test assertions
  "@typescript-eslint/unbound-method": "off",
  // Allows uninitialized variables in test setup
  "@typescript-eslint/init-declarations": "off",
  // Permits flexible type assertions in tests
  "@typescript-eslint/consistent-type-assertions": "off",
  // Allows promise executor returns in test code
  "no-promise-executor-return": "off",
  // Permits awaiting non-promises in tests
  "@typescript-eslint/await-thenable": "off",
  // Allows void expressions in test assertions
  "@typescript-eslint/no-confusing-void-expression": "off",
  // Permits omitting return types in test functions
  "@typescript-eslint/explicit-function-return-type": "off",
};

/** Include TypeScript ESLint configs */
const strictConfig = configs.strict;
const stylisticConfig = configs.stylistic;

export default [
  /** Global ignores */
  {
    ignores: [
      "node_modules/*",
      "dist/*",
      "**/*.js",
      "eslint.config.mts",
      "**/*.spec.ts",
      "**/*.sh",
    ],
  },
  /** TypeScript ESLint configs */
  ...strictConfig,
  ...stylisticConfig,
  /** Base configuration */
  {
    name: "base",
    settings: {
      "import/parsers": {
        "@typescript-eslint/parser": [".ts"],
      },
      "import/resolver": {
        typescript: {},
      },
      "import/ignore": ["node_modules", "mathjs"],
      "import/cache": { lifetime: "∞" }, // Cache import resolution
    },
    languageOptions: {
      globals: {
        ...globals.node,
        ...globals.es2021,
        Bun: false,
      },
      parser: tsParser,
      parserOptions: {
        project: "projects/*/tsconfig.json",
        tsconfigRootDir: __dirname,
      },
    },
    plugins: {
      import: fixupPluginRules(_import),
      "@typescript-eslint": typescriptEslintPlugin,
    },
    rules: {
      ...appRules.possibleProblems,
      ...appRules.bestPractices,
      ...appRules.formatting,
      ...appRules.imports,
      ...appRules.typeSafety,
      ...appRules.asyncPromises,
    },
  },
  /** Test files configuration */
  {
    name: "vpm/tests",
    files: ["**/*.spec.ts"],
    languageOptions: {
      globals: {
        ...globals.node,
        ...globals.es2021,
        Bun: true,
      },
    },
    rules: testRules,
  },
];

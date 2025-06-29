import js from '@eslint/js';
import importPlugin from 'eslint-plugin-import';
import prettier from 'eslint-plugin-prettier';
import globals from 'globals';
// eslint-disable-next-line import/no-unresolved
import tseslint from 'typescript-eslint';

const config = tseslint.config({
  extends: [
    importPlugin.flatConfigs.recommended,
    js.configs.recommended,
    ...tseslint.configs.recommended,
  ],
  files: ['**/*.js', '**/*.ts', '**/*.tsx'],
  ignores: ['node_modules'],
  languageOptions: {
    ecmaVersion: 2020,
    globals: globals.browser,
  },
  plugins: { prettier },
  rules: {
    '@typescript-eslint/ban-ts-comment': 'off',
    '@typescript-eslint/no-empty-object-type': 'warn',
    '@typescript-eslint/no-unnecessary-type-constraint': 'warn',
    '@typescript-eslint/no-unsafe-function-type': 'warn',
    '@typescript-eslint/no-unused-expressions': 'off',
    '@typescript-eslint/no-wrapper-object-types': 'warn',
    curly: ['error', 'multi'],
    'import/namespace': 'off',
    'import/no-named-as-default': 0,
    'import/order': [
      'error',
      {
        alphabetize: {
          order: 'asc',
          caseInsensitive: true,
        },
        groups: [
          'builtin',
          'external',
          'internal',
          ['sibling', 'parent'],
          'index',
          'unknown',
        ],
        'newlines-between': 'always',
      },
    ],
    'jsx-quotes': 0,
    'no-constant-condition': ['error', { checkLoops: true }],
    'no-use-before-define': 'off',
    'no-void': [
      'error',
      {
        allowAsStatement: true,
      },
    ],
    'prettier/prettier': 'warn',
  },
});

export default config;

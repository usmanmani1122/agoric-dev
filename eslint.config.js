import { fixupConfigRules } from '@eslint/compat';
import { FlatCompat } from '@eslint/eslintrc';
import js from '@eslint/js';
import prettier from 'eslint-plugin-prettier';
import reactHooks from 'eslint-plugin-react-hooks';
import reactRefresh from 'eslint-plugin-react-refresh';
import globals from 'globals';
import tseslint from 'typescript-eslint';

const flatCompat = new FlatCompat();

const config = tseslint.config(
  {
    ignores: ['**/.next', 'node_modules'],
  },
  {
    settings: {
      next: {
        rootDir: '*/',
      },
    },
  },
  ...fixupConfigRules(flatCompat.extends('eslint-config-next')),
  {
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    files: ['**/*.js', '**/*.ts', '**/*.tsx'],
    languageOptions: {
      ecmaVersion: 2020,
      globals: globals.browser,
    },
    plugins: { prettier, 'react-refresh': reactRefresh },
    rules: {
      ...reactHooks.configs.recommended.rules,
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
      'react-refresh/only-export-components': [
        'warn',
        { allowConstantExport: true },
      ],
    },
  },
);

export default config;

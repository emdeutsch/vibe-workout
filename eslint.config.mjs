import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import globals from 'globals';

export default tseslint.config(
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    languageOptions: {
      globals: {
        ...globals.node,
      },
    },
  },
  {
    rules: {
      // Allow unused vars prefixed with underscore
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
      // Prefer const over let when possible
      'prefer-const': 'error',
      // Allow console in backend services
      'no-console': 'off',
      // Allow var in declare global
      'no-var': 'off',
    },
  },
  {
    ignores: [
      'node_modules/**',
      '**/dist/**',
      'apps/**', // Swift apps
      '.turbo/**',
      'supabase/**',
    ],
  }
);

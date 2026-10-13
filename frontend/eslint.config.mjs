import parser from '@typescript-eslint/parser';
import hooks from 'eslint-plugin-react-hooks';

export default [
  { ignores: ['.next/**', 'node_modules/**'] },
  {
    files: ['src/**/*.{ts,tsx}'],
    plugins: { 'react-hooks': hooks },
    languageOptions: { parser, parserOptions: { ecmaVersion: 'latest', sourceType: 'module', ecmaFeatures: { jsx: true } } },
    rules: { 'no-debugger': 'error', 'no-constant-condition': 'error', 'react-hooks/exhaustive-deps': 'warn', 'react-hooks/rules-of-hooks': 'error' },
  },
];

import type { Config } from 'tailwindcss';

const config: Config = {
  darkMode: 'class',
  content: ['./src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        bg: 'var(--bg)',
        surface: 'var(--surface)',
        'surface-2': 'var(--surface-2)',
        'surface-3': 'var(--surface-3)',
        border: 'var(--border)',
        'border-soft': 'var(--border-soft)',
        text: 'var(--text)',
        muted: 'var(--muted)',
        subtle: 'var(--subtle)',
        primary: {
          DEFAULT: 'var(--primary)',
          hover: 'var(--primary-hover)',
          foreground: 'var(--primary-foreground)',
          soft: 'var(--primary-soft)'
        },
        accent: {
          DEFAULT: 'var(--accent)',
          soft: 'var(--accent-soft)'
        },
        success: 'var(--success)',
        warning: 'var(--warning)',
        danger: 'var(--danger)',
        info: 'var(--info)',
        ring: 'var(--ring)',
        code: {
          bg: 'var(--code-bg)',
          text: 'var(--code-text)'
        }
      },
      borderRadius: {
        lg: '0.7rem',
        xl: '0.85rem',
        '2xl': '1.1rem'
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', '-apple-system', 'Segoe UI', 'sans-serif'],
        serif: ['Tiempos Text', 'Source Serif Pro', 'Georgia', 'Cambria', 'Times New Roman', 'serif'],
        mono: ['JetBrains Mono', 'Fira Code', 'Consolas', 'Menlo', 'monospace']
      },
      boxShadow: {
        soft: '0 1px 2px rgba(0,0,0,0.04), 0 6px 18px -10px rgba(0,0,0,0.12)',
        elevated: '0 2px 4px rgba(0,0,0,0.05), 0 12px 32px -14px rgba(0,0,0,0.18)',
        glow: '0 0 0 1px var(--ring), 0 8px 30px -12px var(--primary)'
      },
      keyframes: {
        'fade-in': {
          from: { opacity: '0', transform: 'translateY(6px)' },
          to: { opacity: '1', transform: 'translateY(0)' }
        },
        shimmer: {
          '100%': { transform: 'translateX(100%)' }
        }
      },
      animation: {
        'fade-in': 'fade-in 0.35s ease both',
        shimmer: 'shimmer 1.5s infinite'
      }
    }
  },
  plugins: []
};

export default config;

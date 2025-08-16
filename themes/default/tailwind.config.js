/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["../../**/*.{html,dcz}"],
  theme: {
    fontFamily: {
      sans: "var(--font-sans)",
      mono: "var(--font-mono)",
    },
    extend: {
      colors: {
        bg: "var(--color-bg)",
        fg: "var(--color-fg)",
        muted: "var(--color-muted)",
        accent: "var(--color-accent)",
      },
      borderRadius: { DEFAULT: "var(--radius)" },
      spacing: {
        1: "var(--space-1)",
        2: "var(--space-2)",
        3: "var(--space-3)",
        4: "var(--space-4)",
        6: "var(--space-6)",
        8: "var(--space-8)",
      },
    },
  },
  corePlugins: { preflight: false }, // we use preflight.css instead
  plugins: [],
};

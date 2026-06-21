import { Html, Head, Main, NextScript } from 'next/document';

export default function Document() {
  return (
    <Html lang="es" suppressHydrationWarning>
      <Head>
        <meta charSet="utf-8" />
        <meta name="description" content="Sistema educativo basado en LLMs para Python" />
      </Head>
      <body>
        <Main />
        <NextScript />
      </body>
    </Html>
  );
}

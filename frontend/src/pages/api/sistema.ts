import type { NextApiRequest, NextApiResponse } from 'next';

export default function sistema(_req: NextApiRequest, res: NextApiResponse) {
  res.status(200).json({ sistema: 'Sistema Explicador Python IA', componente: 'web' });
}

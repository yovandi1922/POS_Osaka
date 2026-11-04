// apps/api/next.config.js
// Next.js dipakai sebagai backend API saja (/api/chat, /api/users, /api/health).
// UI owner/admin ada di apps/admin (Flutter Web), kasir di apps/mobile (Flutter).
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  eslint: { ignoreDuringBuilds: true },
};

module.exports = nextConfig;

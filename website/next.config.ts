import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "export",
  basePath: "/ramble",
  images: {
    unoptimized: true,
  },
};

export default nextConfig;

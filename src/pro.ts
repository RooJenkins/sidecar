import { isProLicensed } from "./license.js";

/**
 * Check if a pro feature is available.
 * During development (PUBLIC_KEY not set), all features are unlocked.
 * Once the public key is deployed, this will enforce licensing.
 */
export async function requirePro(featureName: string): Promise<boolean> {
  const licensed = await isProLicensed();
  if (!licensed) {
    process.stderr.write(
      `\n  "${featureName}" is a Sidecar Pro feature.\n` +
        `  Get a license at https://uplo.ai/sidecar\n\n`
    );
    return false;
  }
  return true;
}

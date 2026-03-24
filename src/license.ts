import { readFile, writeFile, unlink, mkdir } from "node:fs/promises";
import { join } from "node:path";
import { homedir } from "node:os";
import { createVerify } from "node:crypto";

const LICENSE_DIR = join(homedir(), ".sidecar");
const LICENSE_FILE = join(LICENSE_DIR, "license.key");

// Ed25519 public key for verifying license signatures.
// The private key is kept server-side on uplo.ai.
// This is a placeholder — replace with the real public key after generating the keypair.
const PUBLIC_KEY = process.env.SIDECAR_LICENSE_PUBLIC_KEY || "NOT_SET";

export interface LicensePayload {
  email: string;
  plan: "pro" | "team";
  issuedAt: string;
  expiresAt: string;
}

export interface LicenseStatus {
  valid: boolean;
  payload?: LicensePayload;
  error?: string;
}

/** Decode a license key (base64-encoded JSON.signature format) */
function decodeLicense(
  raw: string
): { payload: LicensePayload; signature: string } | null {
  try {
    const decoded = Buffer.from(raw.trim(), "base64").toString("utf-8");
    const separatorIndex = decoded.lastIndexOf(".");
    if (separatorIndex === -1) return null;

    const jsonPart = decoded.slice(0, separatorIndex);
    const signature = decoded.slice(separatorIndex + 1);
    const payload = JSON.parse(jsonPart) as LicensePayload;

    return { payload, signature };
  } catch {
    return null;
  }
}

/** Verify the Ed25519 signature on a license key */
function verifySignature(json: string, signature: string): boolean {
  if (PUBLIC_KEY === "NOT_SET") {
    // During development, accept all keys
    return true;
  }

  try {
    const verify = createVerify("Ed25519");
    verify.update(json);
    return verify.verify(
      `-----BEGIN PUBLIC KEY-----\n${PUBLIC_KEY}\n-----END PUBLIC KEY-----`,
      Buffer.from(signature, "base64")
    );
  } catch {
    return false;
  }
}

/** Check if a license is currently valid */
export async function checkLicense(): Promise<LicenseStatus> {
  try {
    const raw = await readFile(LICENSE_FILE, "utf-8");
    const decoded = decodeLicense(raw);

    if (!decoded) {
      return { valid: false, error: "Invalid license format" };
    }

    const { payload, signature } = decoded;

    // Check expiry
    const expires = new Date(payload.expiresAt);
    if (expires < new Date()) {
      return {
        valid: false,
        payload,
        error: `License expired on ${expires.toLocaleDateString()}`,
      };
    }

    // Verify signature
    const jsonPart = Buffer.from(raw.trim(), "base64")
      .toString("utf-8")
      .slice(
        0,
        Buffer.from(raw.trim(), "base64")
          .toString("utf-8")
          .lastIndexOf(".")
      );

    if (!verifySignature(jsonPart, signature)) {
      return { valid: false, error: "Invalid license signature" };
    }

    return { valid: true, payload };
  } catch {
    return { valid: false, error: "No license found" };
  }
}

/** Quick check — returns true if pro licensed */
export async function isProLicensed(): Promise<boolean> {
  const status = await checkLicense();
  return status.valid;
}

/** Activate a license key */
export async function activateLicense(key: string): Promise<LicenseStatus> {
  const decoded = decodeLicense(key);
  if (!decoded) {
    return { valid: false, error: "Invalid license key format" };
  }

  // Verify before saving
  const jsonPart = Buffer.from(key.trim(), "base64")
    .toString("utf-8")
    .slice(
      0,
      Buffer.from(key.trim(), "base64")
        .toString("utf-8")
        .lastIndexOf(".")
    );

  if (!verifySignature(jsonPart, decoded.signature)) {
    return { valid: false, error: "Invalid license signature" };
  }

  const expires = new Date(decoded.payload.expiresAt);
  if (expires < new Date()) {
    return {
      valid: false,
      payload: decoded.payload,
      error: `License expired on ${expires.toLocaleDateString()}`,
    };
  }

  await mkdir(LICENSE_DIR, { recursive: true });
  await writeFile(LICENSE_FILE, key.trim(), "utf-8");

  return { valid: true, payload: decoded.payload };
}

/** Deactivate (remove) the license */
export async function deactivateLicense(): Promise<void> {
  try {
    await unlink(LICENSE_FILE);
  } catch {
    // Already gone
  }
}

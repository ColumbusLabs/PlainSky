import type { Notification } from "./alerts.ts";

export interface APNsConfig {
  teamId: string;
  keyId: string;
  privateKey: string; // PEM contents of the .p8 file
  bundleId: string;
}

export type SendResult = "sent" | "invalid-token" | "failed";

const HOSTS = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
} as const;

// Apple accepts a provider token for up to an hour; refresh well before that.
const TOKEN_LIFETIME_SECONDS = 40 * 60;
let cachedToken: { value: string; issuedAt: number; keyId: string } | null = null;

function base64url(bytes: ArrayBuffer | Uint8Array): string {
  const array = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = "";
  for (const byte of array) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function providerToken(config: APNsConfig, now: number): Promise<string> {
  if (cachedToken && cachedToken.keyId === config.keyId && now - cachedToken.issuedAt < TOKEN_LIFETIME_SECONDS) {
    return cachedToken.value;
  }

  const pem = config.privateKey.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );

  const encoder = new TextEncoder();
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: config.keyId })));
  const claims = base64url(encoder.encode(JSON.stringify({ iss: config.teamId, iat: now })));
  const signingInput = `${header}.${claims}`;
  // WebCrypto returns the raw r||s signature that JWT ES256 expects.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(signingInput)
  );

  const value = `${signingInput}.${base64url(signature)}`;
  cachedToken = { value, issuedAt: now, keyId: config.keyId };
  return value;
}

export async function send(
  config: APNsConfig,
  environment: "sandbox" | "production",
  deviceToken: string,
  notification: Notification,
  now: number
): Promise<SendResult> {
  const payload = {
    aps: {
      alert: {
        title: notification.title,
        subtitle: notification.subtitle,
        body: notification.body,
      },
      sound: "default",
      "thread-id": "alerts",
      "interruption-level": notification.timeSensitive ? "time-sensitive" : "active",
    },
    alertID: notification.alertId,
  };

  const response = await fetch(`${HOSTS[environment]}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await providerToken(config, now)}`,
      "apns-topic": config.bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      // Undelivered alerts are useless once NWS expires them.
      "apns-expiration": String(notification.expiresAt),
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (response.ok) return "sent";

  const reason = await response.json<{ reason?: string }>().catch(() => ({ reason: undefined }));
  console.warn("APNs rejected push", response.status, reason.reason);
  if (response.status === 410 || reason.reason === "BadDeviceToken" || reason.reason === "Unregistered") {
    return "invalid-token";
  }
  return "failed";
}

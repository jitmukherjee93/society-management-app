/**
 * ============================================================================
 * FIREBASE CLOUD FUNCTIONS - SOCIETY MANAGEMENT REAL-TIME FCM DISPATCHER
 * ============================================================================
 * This Cloud Function listens to newly created documents in the `notifications`
 * collection and immediately dispatches native, high-priority Firebase Cloud
 * Messaging (FCM) pushes to users' Android devices.
 *
 * Core Capabilities:
 * 1. Native OS Status Bar & Hood Delivery:
 *    - Sends dual-payload (notification + data) messages with `priority: 'high'`
 *      and targeting Android channels ('society_general_channel' & 'society_emergency_channel').
 *    - Delivers alerts even when the app is minimized, phone is locked, or app process is killed.
 *
 * 2. Intelligent Recipient Resolution:
 *    - RESIDENT: Matches by `targetUid`, `targetUids`, or flat number (e.g. 'B-312').
 *    - GUARD: Matches all security gate personnel for resident approval/denial alerts.
 *    - ADMIN: Matches managing committee members for payment approvals & urgent alerts.
 *    - ALL / EMERGENCY: Broadcasts to all registered devices in the society.
 *
 * 3. Dead Token Pruning:
 *    - Automatically removes invalid or uninstalled device tokens from Firestore
 *      when FCM reports 'registration-token-not-registered'.
 * ============================================================================
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

// Initialize Firebase Admin SDK singleton
admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();
const FieldValue = admin.firestore.FieldValue;

/**
 * Normalizes flat numbers (e.g., "b 312", "b-312", "B-312") to standard "B-312" format.
 */
function normalizeFlat(flat) {
  if (!flat) return "";
  const cleaned = String(flat).trim().toUpperCase().replace(/\s+/g, "");
  const match = cleaned.match(/^([A-Z]+)[-_\s]*([0-9]+)$/);
  if (match) {
    return `${match[1]}-${match[2]}`;
  }
  return cleaned;
}

/**
 * Cloud Function triggered on creation of any document in `/notifications/{notificationId}`.
 */
exports.onNotificationCreated = functions
  .region("asia-south1")
  .firestore.document("notifications/{notificationId}")
  .onCreate(async (snapshot, context) => {
    if (!snapshot || !snapshot.data) {
      console.log("[FCM Dispatcher] No snapshot data available, exiting.");
      return;
    }

    const notifId = context.params.notificationId;
    const notifData = snapshot.data() || {};

    const title = notifData.title || "Society Notification";
    const messageText = notifData.message || "";
    const type = (notifData.type || "GENERAL").toUpperCase();
    const targetRole = (notifData.targetRole || "RESIDENT").toUpperCase();
    const flatNumber = notifData.flatNumber ? normalizeFlat(notifData.flatNumber) : "";
    const targetUid = notifData.targetUid || null;
    const targetUids = Array.isArray(notifData.targetUids) ? notifData.targetUids : [];

    const isEmergency = type === "EMERGENCY" || type === "SOS";

    // Determine if this notification is for a visitor entry approval or gate pass request.
    // Visitor approvals require immediate attention from the resident, so we route them
    // to a dedicated channel with maximum priority and a custom doorbell ringtone.
    const isVisitorRequest =
      type === "VISITOR_CHECK_IN" ||
      type === "VISITOR_APPROVAL" ||
      type === "VISITOR" ||
      type === "GUEST_ENTRY" ||
      type === "PARKING_REQUEST" ||
      notifData.isWalkIn === true ||
      notifData.isWalkIn === "true" ||
      notifData.approvalStatus === "PENDING";

    console.log(
      `[FCM Dispatcher] Processing notification ID: ${notifId}, Type: ${type}, Role: ${targetRole}, Flat: ${flatNumber}`
    );

    // Set to collect unique FCM registration tokens and map them to UIDs for pruning
    const tokenToUidMap = new Map();

    try {
      // ----------------------------------------------------------------------
      // 1. RESOLVE RECIPIENTS BASED ON TARGET ROLE AND FLAT
      // ----------------------------------------------------------------------
      if (targetRole === "ALL" || isEmergency) {
        // Broadcast: query all users who have registered an FCM device token
        const usersSnap = await db.collection("users").get();
        usersSnap.forEach((doc) => {
          const data = doc.data();
          const uid = doc.id;
          if (Array.isArray(data.fcmTokens)) {
            data.fcmTokens.forEach((t) => {
              if (t && typeof t === "string") tokenToUidMap.set(t, uid);
            });
          }
          if (data.fcmToken && typeof data.fcmToken === "string") {
            tokenToUidMap.set(data.fcmToken, uid);
          }
        });
      } else if (targetRole === "ADMIN") {
        // Query users with ADMIN role
        const adminSnap = await db
          .collection("users")
          .where("role", "in", ["ADMIN", "Admin", "admin"])
          .get();
        adminSnap.forEach((doc) => {
          const data = doc.data();
          const uid = doc.id;
          if (Array.isArray(data.fcmTokens)) {
            data.fcmTokens.forEach((t) => {
              if (t && typeof t === "string") tokenToUidMap.set(t, uid);
            });
          }
          if (data.fcmToken && typeof data.fcmToken === "string") {
            tokenToUidMap.set(data.fcmToken, uid);
          }
        });
      } else if (targetRole === "GUARD") {
        // Query users with GUARD role
        const guardSnap = await db
          .collection("users")
          .where("role", "in", ["GUARD", "Guard", "guard"])
          .get();
        guardSnap.forEach((doc) => {
          const data = doc.data();
          const uid = doc.id;
          if (Array.isArray(data.fcmTokens)) {
            data.fcmTokens.forEach((t) => {
              if (t && typeof t === "string") tokenToUidMap.set(t, uid);
            });
          }
          if (data.fcmToken && typeof data.fcmToken === "string") {
            tokenToUidMap.set(data.fcmToken, uid);
          }
        });
      } else {
        // RESIDENT recipient resolution
        const candidateUids = new Set();
        if (targetUid) candidateUids.add(targetUid);
        targetUids.forEach((u) => {
          if (typeof u === "string" && u.length > 5 && !u.includes("-")) {
            candidateUids.add(u);
          }
        });

        // A. Look up by direct target UID(s)
        for (const uid of candidateUids) {
          try {
            const userDoc = await db.collection("users").doc(uid).get();
            if (userDoc.exists) {
              const data = userDoc.data() || {};
              if (Array.isArray(data.fcmTokens)) {
                data.fcmTokens.forEach((t) => {
                  if (t && typeof t === "string") tokenToUidMap.set(t, uid);
                });
              }
              if (data.fcmToken && typeof data.fcmToken === "string") {
                tokenToUidMap.set(data.fcmToken, uid);
              }
            }
          } catch (err) {
            console.error(`[FCM Dispatcher] Error fetching user doc ${uid}:`, err);
          }
        }

        // B. Look up all residents belonging to the destination flat number (e.g., 'B-312')
        if (flatNumber) {
          const flatVariants = [
            flatNumber,
            flatNumber.replace("-", ""),
            flatNumber.toLowerCase(),
          ];

          for (const fVar of flatVariants) {
            const flatSnap = await db
              .collection("users")
              .where("flatNumber", "==", fVar)
              .get();

            flatSnap.forEach((doc) => {
              const data = doc.data();
              const uid = doc.id;
              if (Array.isArray(data.fcmTokens)) {
                data.fcmTokens.forEach((t) => {
                  if (t && typeof t === "string") tokenToUidMap.set(t, uid);
                });
              }
              if (data.fcmToken && typeof data.fcmToken === "string") {
                tokenToUidMap.set(data.fcmToken, uid);
              }
            });
          }
        }
      }

      const tokens = Array.from(tokenToUidMap.keys()).filter(
        (t) => t && t.length > 10
      );

      if (tokens.length === 0) {
        console.log(
          `[FCM Dispatcher] No registered FCM tokens found for notification: ${notifId}`
        );
        return;
      }

      console.log(
        `[FCM Dispatcher] Dispatching notification to ${tokens.length} device token(s)...`
      );

      // ----------------------------------------------------------------------
      // 2. CONSTRUCT DATA PAYLOAD (ALL VALUES STRINGIFIED FOR FCM PROTOCOL)
      // ----------------------------------------------------------------------
      const sanitizedData = {
        id: String(notifId),
        title: String(title),
        message: String(messageText),
        type: String(type),
        flatNumber: String(flatNumber),
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      };

      // Safely serialize extra attributes into the data payload
      for (const [key, value] of Object.entries(notifData)) {
        if (
          value !== undefined &&
          value !== null &&
          typeof value !== "object" &&
          !sanitizedData[key]
        ) {
          sanitizedData[key] = String(value);
        }
      }

      // ----------------------------------------------------------------------
      // 3. DISPATCH HIGH-PRIORITY MULTICAST MESSAGE
      // ----------------------------------------------------------------------
      // FCM allows up to 500 tokens per multicast batch
      const BATCH_SIZE = 500;
      for (let i = 0; i < tokens.length; i += BATCH_SIZE) {
        const batchTokens = tokens.slice(i, i + BATCH_SIZE);

        // CRITICAL FOR SINGLE NOTIFICATION WITH APPROVE/DENY BUTTONS ON ANDROID:
        // For visitor clearance requests, omit the top-level 'notification' block.
        // This delivers a pure high-priority data message to Android, preventing
        // Google Play Services from posting a duplicate, buttonless notification.
        // Flutter's background handler receives the data and posts the ONE and ONLY
        // notification with the interactive Approve / Leave at Gate / Deny buttons.
        //
        // iOS COMPATIBILITY — WHY WE NEED THE `apns` BLOCK:
        // iOS APNs DROPS data-only messages (no notification block) silently when
        // the app is killed or suspended. To wake the device and show a banner on iOS,
        // the FCM message MUST include an `apns.payload.aps.alert` block.
        // We use `content-available: 1` alongside the alert so:
        //   (a) iOS shows a native OS banner regardless of app state.
        //   (b) The iOS background handler also fires for any supplemental data work.
        // The `apns` block is completely ignored by Android, so there is zero risk of
        // duplicates on Android.
        //
        // CATEGORY on iOS unlocks the native Approve / Deny inline action buttons
        // in the iOS notification centre — matching the Android interactive buttons.
        const visitorApnsCategory = isVisitorRequest ? "VISITOR_APPROVAL_CATEGORY" : undefined;
        const multicastMessage = {
          tokens: batchTokens,
          // Top-level notification: omitted for visitor requests on Android (prevents
          // buttonless duplicate); present for all other notification types.
          ...(isVisitorRequest ? {} : {
            notification: {
              title: title,
              body: messageText,
            },
          }),
          data: sanitizedData,
          android: {
            priority: "high",
            ...(isVisitorRequest ? {} : {
              notification: {
                channelId: isEmergency ? "society_emergency_channel" : "society_general_channel",
                priority: isEmergency ? "max" : "high",
                sound: "default",
                defaultSound: true,
                defaultVibrateTimings: true,
                visibility: "public",
                tag: notifId,
              },
            }),
          },
          // iOS-SPECIFIC PUSH CONFIGURATION
          // The `apns` block is required for iOS to wake the device and display
          // a banner/alert when the app is in the background or completely killed.
          // Without this block, iOS APNs silently discards the message.
          apns: {
            headers: {
              // `apns-priority: 10` = immediate delivery (vs 5 = low priority).
              // Required for content-available and time-sensitive notifications.
              "apns-priority": "10",
              // `apns-push-type` must be 'alert' for visible banners or 'background'
              // for silent background wakes. We always use 'alert' so the user sees
              // the notification immediately.
              "apns-push-type": "alert",
            },
            payload: {
              aps: {
                // `alert` causes iOS to display a native banner/lock-screen notification.
                // This is mandatory for the notification to be visible when the app is killed.
                alert: {
                  title: title,
                  body: messageText,
                },
                sound: isEmergency ? "default" : "default",
                // `badge` count on the app icon (1 for any new notification)
                badge: 1,
                // `content-available: 1` tells iOS to wake the app in the background
                // so the Flutter background handler can process the data payload
                // (e.g., storing the visitor request details for the popup dialog).
                "content-available": 1,
                // `category` links to the UNNotificationCategory registered in the
                // Flutter plugin (DarwinNotificationCategory 'VISITOR_APPROVAL_CATEGORY'),
                // which adds inline 'Approve' / 'Leave at Gate' / 'Deny' action buttons
                // directly in the iOS notification centre.
                ...(visitorApnsCategory ? { category: visitorApnsCategory } : {}),
              },
            },
          },
        };

        const response = await messaging.sendEachForMulticast(multicastMessage);
        console.log(
          `[FCM Dispatcher] Batch sent: ${response.successCount} succeeded, ${response.failureCount} failed.`
        );

        // ----------------------------------------------------------------------
        // 4. CLEAN UP EXPIRED OR UNINSTALLED TOKENS
        // ----------------------------------------------------------------------
        if (response.failureCount > 0) {
          const deadTokensByUid = new Map();

          response.responses.forEach((resp, idx) => {
            if (!resp.success) {
              const errorCode = resp.error ? resp.error.code : "";
              if (
                errorCode === "messaging/registration-token-not-registered" ||
                errorCode === "messaging/invalid-registration-token"
              ) {
                const deadToken = batchTokens[idx];
                const uid = tokenToUidMap.get(deadToken);
                if (uid) {
                  if (!deadTokensByUid.has(uid)) {
                    deadTokensByUid.set(uid, []);
                  }
                  deadTokensByUid.get(uid).push(deadToken);
                }
              }
            }
          });

          // Prune dead tokens from user documents
          for (const [uid, deadTokens] of deadTokensByUid.entries()) {
            try {
              await db
                .collection("users")
                .doc(uid)
                .update({
                  fcmTokens: FieldValue.arrayRemove(...deadTokens),
                });
              console.log(
                `[FCM Dispatcher] Pruned ${deadTokens.length} stale token(s) for user: ${uid}`
              );
            } catch (pruneErr) {
              console.error(
                `[FCM Dispatcher] Error pruning tokens for user ${uid}:`,
                pruneErr
              );
            }
          }
        }
      }
    } catch (error) {
      console.error("[FCM Dispatcher] Unhandled error during notification dispatch:", error);
    }
  }
);


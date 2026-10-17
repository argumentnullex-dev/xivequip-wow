# XIVEquip 2.0.2

- Fix persistent "Loading item data" and blocked gear recommendations on WoW Retail 12.1.5.
- Prefer current C_Item APIs for item metadata, stats, and item levels while retaining legacy fallbacks.
- Keep normal item-data retries and Blizzard bind confirmations working with the current APIs.
- Preserve item stats in diagnostic captures when deprecated global APIs are unavailable or fail.
- Add Retail 12.1.5 to the supported client metadata. Built-in scales are unchanged.

# XIVEquip 2.0.1

- Reject weapons the current class or specialization cannot use, including the Devourer dagger exception.
- Refresh cached gear facts when item stats finish loading or a physical item changes level.
- Use the actual physical item level for scaled gear instead of an unscaled link value.
- Recognize additional Retail leech stat tokens and handle unavailable stat APIs safely.
- Allow Wishlist proc/on-use items with zero calculable stat value to compete with current gear. Wishlist retains a ten-percent margin over the larger of its base score and current gear; Avoidlist still excludes items.
- Include richer candidate, stat, and planning diagnostics in captured fixtures.
- Display packaged source revision in /xive status.

Built-in scales and supported client metadata are unchanged (Retail 12.0.7 and 12.1.0). In-game validation is required before publication.

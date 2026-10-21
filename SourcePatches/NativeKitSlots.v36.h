#pragma once

#include <cstdint>

namespace scropts { namespace kits {

struct SlotMetadata {
    std::uint32_t weapon = 0;
    std::uint32_t variant = 0;
    std::uint32_t sort = 0;
    std::uint32_t readOnly = 0;
    std::uint32_t camo = 0;
    std::uint32_t reticle = 0;
};

struct EmptySlotSearch {
    int readable = 0;
    int matchingWeapons = 0;
    int cleanUnused = 0;
    int candidate = -1;
    int unreadableSlot = -1;
};

// Uses the v35 empty-slot definition. Never treats an unreadable or partially
// initialized entry as spare capacity. The adapters do all actual DDL reads.
template<class Exists, class Metadata, class Attachment>
EmptySlotSearch FindEmptySlot(std::uint32_t weaponId, Exists exists,
                             Metadata metadata, Attachment attachment) {
    EmptySlotSearch result;
    if (!weaponId) return result;
    int firstEmpty = -1;
    for (int slot = 0; slot < 160; ++slot) {
        if (!exists(slot)) break;
        ++result.readable;
        SlotMetadata value;
        if (!metadata(slot, value)) {
            result.unreadableSlot = slot;
            return result;
        }
        if (value.weapon == weaponId) ++result.matchingWeapons;
        if (value.weapon != 0 || value.variant != static_cast<std::uint32_t>(slot) ||
            value.sort != 0 || value.readOnly != 0 || value.camo != 0 || value.reticle != 0)
            continue;
        bool clean = true;
        for (int part = 0; part < 8; ++part) {
            std::uint32_t id = 0, look = 0;
            if (!attachment(slot, part, id, look)) {
                result.unreadableSlot = slot;
                return result;
            }
            if (id != 0 || look != 0) clean = false;
        }
        if (clean) {
            ++result.cleanUnused;
            if (firstEmpty < 0) firstEmpty = slot;
        }
    }
    if (result.readable == 50 && result.matchingWeapons == 0)
        result.candidate = firstEmpty;
    return result;
}

}} // namespace scropts::kits

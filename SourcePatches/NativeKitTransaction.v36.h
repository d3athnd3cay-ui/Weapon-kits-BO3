#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

// Platform-independent transaction policy used by the native DDL writer.
// Storage_Write is an engine request, not a durability guarantee. This helper
// never represents a successful readback as proof of persistence after restart.
namespace scropts { namespace kits {

enum class WriteStatus {
    Committed,
    PreconditionChanged,
    FieldWriteFailed,
    IdentityChanged,
    PersistFailed,
    PostPersistMismatch
};

struct WriteResult {
    WriteStatus status = WriteStatus::PreconditionChanged;
    std::size_t attempted = 0;
    bool rollbackVerified = false;
    bool persistenceAttempted = false;
};

template<class Read, class Write, class Guard, class Identity, class Persist>
WriteResult ExecuteWrite(const std::vector<std::uint32_t>& before,
                         const std::vector<std::uint32_t>& after,
                         Read read, Write write, Guard guard,
                         Identity identity, Persist persist) {
    WriteResult result;
    if (before.empty() || before.size() != after.size()) return result;

    const auto matches = [&](const std::vector<std::uint32_t>& expected) {
        for (std::size_t i = 0; i < expected.size(); ++i) {
            std::uint32_t actual = 0;
            if (!guard() || !read(i, actual) || actual != expected[i]) return false;
        }
        return true;
    };
    const auto rollback = [&]() {
        if (!result.attempted) return;
        bool restored = true;
        // In creation, weaponIndex is written last: remove that identity first
        // when restoring, before dismantling the attachment/camo fields.
        for (std::size_t i = result.attempted; i > 0; --i) {
            if (!guard()) { restored = false; break; }
            if (!write(i - 1, before[i - 1])) restored = false;
        }
        result.rollbackVerified = restored && matches(before);
    };
    // A backup can take time. Refuse a stale plan without changing any fields.
    if (!matches(before)) return result;
    for (std::size_t i = 0; i < after.size(); ++i) {
        if (!guard()) {
            result.status = WriteStatus::PreconditionChanged;
            rollback();
            return result;
        }
        result.attempted = i + 1; // A failing setter may already have mutated it.
        std::uint32_t actual = 0;
        if (!write(i, after[i])) {
            result.status = WriteStatus::FieldWriteFailed;
            rollback();
            return result;
        }
        if (!guard()) {
            result.status = WriteStatus::PreconditionChanged;
            rollback();
            return result;
        }
        if (!read(i, actual) || actual != after[i]) {
            result.status = WriteStatus::FieldWriteFailed;
            rollback();
            return result;
        }
    }
    // Validate all fields together; immediate per-field readback cannot catch
    // an unexpected overlap or a later setter clobbering an earlier field.
    if (!matches(after)) {
        result.status = WriteStatus::FieldWriteFailed;
        rollback();
        return result;
    }
    if (!guard() || !identity()) {
        result.status = WriteStatus::IdentityChanged;
        rollback();
        return result;
    }
    result.persistenceAttempted = true;
    if (!persist()) {
        result.status = WriteStatus::PersistFailed;
        rollback();
        return result;
    }
    if (!matches(after) || !guard() || !identity()) {
        // Disk state is unknown after the engine accepted a write. Do not
        // silently change memory back and imply that this restored disk data.
        result.status = WriteStatus::PostPersistMismatch;
        return result;
    }
    result.status = WriteStatus::Committed;
    return result;
}

}} // namespace scropts::kits

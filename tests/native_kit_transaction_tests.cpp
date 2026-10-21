#include "../SourcePatches/NativeKitTransaction.v36.h"

#include <algorithm>
#include <cstdint>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

// These tests execute the same transaction helper called by the DLL, using a
// deterministic storage adapter. They do not claim Windows/BO3 integration or
// disk persistence; those need the game and its real DDL/Storage_Write adapter.
namespace {
using scropts::kits::WriteResult;
using scropts::kits::WriteStatus;

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

struct Store {
    // Eight attachment IDs, eight cosmetic IDs and a camo, matching edits.
    std::vector<std::uint32_t> before;
    std::vector<std::uint32_t> after;
    std::vector<std::uint32_t> fields;
    std::vector<std::pair<std::size_t, std::uint32_t>> writes;
    std::vector<std::size_t> initialReads;
    std::function<bool(std::size_t, std::uint32_t&)> onRead;
    std::function<bool(std::size_t, std::uint32_t)> onWrite;
    std::function<bool()> onGuard;
    std::function<bool()> onIdentity;
    std::function<bool()> onPersist;
    int persists = 0;
    int identities = 0;
    bool persisted = false;

    Store() {
        for (std::uint32_t i = 0; i < 8; ++i) {
            before.push_back(i + 1);
            after.push_back(i + 21);
        }
        for (std::uint32_t i = 0; i < 8; ++i) {
            before.push_back(i);
            after.push_back(8 - i);
        }
        before.push_back(13);
        after.push_back(101);
        fields = before;
    }

    WriteResult run() {
        return scropts::kits::ExecuteWrite(before, after,
            [&](std::size_t i, std::uint32_t& value) {
                if (writes.empty()) initialReads.push_back(i);
                if (i >= fields.size()) return false;
                value = fields[i];
                return !onRead || onRead(i, value);
            },
            [&](std::size_t i, std::uint32_t value) {
                writes.emplace_back(i, value);
                if (i >= fields.size()) return false;
                if (onWrite) return onWrite(i, value);
                fields[i] = value;
                return true;
            },
            [&] { return !onGuard || onGuard(); },
            [&] {
                ++identities;
                return !onIdentity || onIdentity();
            },
            [&] {
                ++persists;
                if (onPersist && !onPersist()) return false;
                persisted = true;
                return true;
            });
    }

    void expectReverseRollback(std::size_t attempted) const {
        require(writes.size() == attempted * 2,
                "rollback must address every attempted field exactly once");
        for (std::size_t i = 0; i < attempted; ++i) {
            require(writes[i].first == i, "writes must follow field order");
            require(writes[attempted + i].first == attempted - 1 - i,
                    "rollback must restore fields in reverse order");
            require(writes[attempted + i].second == before[attempted - 1 - i],
                    "rollback must use original field values");
        }
    }
};

void edits_eight_attachments_cosmetics_and_camo() {
    Store store;
    store.onPersist = [&] {
        require(store.fields == store.after,
                "all eight attachments, cosmetics and camo must precede persistence");
        require(store.identities >= 1, "identity must be checked before persistence");
        return true;
    };
    const auto result = store.run();
    require(result.status == WriteStatus::Committed, "valid edit must commit");
    require(result.attempted == 17, "all 17 native edit fields must execute");
    require(result.persistenceAttempted && store.persists == 1,
            "valid edit must persist exactly once");
    require(store.identities >= 2, "identity must be checked after persistence too");
    require(store.fields == store.after, "committed values must match the requested kit");
    require(store.writes.size() == 17, "success must not roll back");
    for (std::size_t i = 0; i < 17; ++i) {
        require(store.writes[i].first == i, "native field order must be preserved");
        require(std::find(store.initialReads.begin(), store.initialReads.end(), i)
                    != store.initialReads.end(),
                "all original fields must be checked before the first setter");
    }
}

void rejects_stale_snapshot_without_writes() {
    Store store;
    store.fields.back() = 99;
    const auto result = store.run();
    require(result.status == WriteStatus::PreconditionChanged,
            "stale snapshot must be rejected");
    require(result.attempted == 0 && store.writes.empty() && store.persists == 0,
            "stale snapshot must cause no writes or persistence");
    require(!result.rollbackVerified && !result.persistenceAttempted,
            "no-write failure must not claim rollback or persistence");
    require(store.fields.back() == 99, "pre-existing changes must be preserved");
}

void rejects_invalid_field_vector_sizes() {
    Store store;
    store.after.pop_back();
    const auto result = store.run();
    require(result.status == WriteStatus::PreconditionChanged,
            "unequal field vector lengths must be rejected");
    require(store.writes.empty() && store.persists == 0,
            "invalid transaction must not mutate storage");
}

void rejects_offline_guard_before_writing() {
    Store store;
    store.onGuard = [] { return false; };
    const auto result = store.run();
    require(result.status == WriteStatus::PreconditionChanged,
            "invalid initial context must be rejected");
    require(store.writes.empty() && store.persists == 0,
            "invalid context must never invoke setters or persistence");
}

void rolls_back_a_setter_that_mutates_then_fails() {
    Store store;
    bool injected = false;
    store.onWrite = [&](std::size_t i, std::uint32_t value) {
        store.fields[i] = value;
        if (!injected && i == 5 && value == store.after[i]) {
            injected = true;
            return false;
        }
        return true;
    };
    const auto result = store.run();
    require(injected && result.status == WriteStatus::FieldWriteFailed,
            "failed setter must fail the transaction even after mutating");
    require(result.attempted == 6 && result.rollbackVerified,
            "rollback must include the setter that reported failure");
    require(store.fields == store.before && store.persists == 0,
            "failed setter must restore originals and avoid persistence");
    store.expectReverseRollback(6);
}

void rolls_back_an_immediate_readback_mismatch() {
    Store store;
    bool injected = false;
    store.onRead = [&](std::size_t i, std::uint32_t& value) {
        if (!injected && i == 4 && value == store.after[i]) {
            injected = true;
            value = 0xFFFF;
        }
        return true;
    };
    const auto result = store.run();
    require(injected && result.status == WriteStatus::FieldWriteFailed,
            "immediate readback mismatch must fail the transaction");
    require(result.rollbackVerified && store.fields == store.before,
            "readback mismatch must restore and verify original values");
    require(store.persists == 0, "mismatched fields must not be persisted");
    store.expectReverseRollback(5);
}

void rolls_back_an_immediate_read_failure() {
    Store store;
    bool injected = false;
    store.onRead = [&](std::size_t i, std::uint32_t& value) {
        if (!injected && i == 4 && value == store.after[i]) {
            injected = true;
            return false;
        }
        return true;
    };
    const auto result = store.run();
    require(injected && result.status == WriteStatus::FieldWriteFailed,
            "unreadable field after a write must fail the transaction");
    require(result.rollbackVerified && store.fields == store.before,
            "read failure must restore original values when context remains valid");
    require(store.persists == 0, "unreadable writes must not be persisted");
}

void detects_late_clobber_before_persisting() {
    Store store;
    store.onWrite = [&](std::size_t i, std::uint32_t value) {
        store.fields[i] = value;
        if (i == 16 && value == store.after[i]) store.fields[0] = 999;
        return true;
    };
    const auto result = store.run();
    require(result.status == WriteStatus::FieldWriteFailed,
            "whole-transaction readback must detect a previously verified field changing");
    require(result.rollbackVerified && store.fields == store.before,
            "late clobber must restore the original kit");
    require(store.persists == 0, "late clobber must not reach persistence");
    store.expectReverseRollback(17);
}

void stops_when_context_guard_is_lost() {
    Store store;
    store.onGuard = [&] { return store.writes.size() < 4; };
    const auto result = store.run();
    require(result.status == WriteStatus::PreconditionChanged,
            "context loss during writes must invalidate the transaction");
    require(!result.rollbackVerified && !result.persistenceAttempted,
            "invalid context must not claim a safe rollback or persistence");
    require(store.writes.size() == 4 && store.persists == 0,
            "no setter, rollback or persistence may use the invalid context");
}

void rolls_back_when_kit_identity_changes() {
    Store store;
    store.onIdentity = [&] { return store.fields != store.after; };
    const auto result = store.run();
    require(result.status == WriteStatus::IdentityChanged,
            "changed or ambiguous kit identity must block persistence");
    require(result.rollbackVerified && store.fields == store.before,
            "identity change must roll back all attempted fields");
    require(store.persists == 0, "changed identity must not be persisted");
    store.expectReverseRollback(17);
}

void reports_failed_rollback() {
    Store store;
    bool injected = false;
    store.onWrite = [&](std::size_t i, std::uint32_t value) {
        if (injected && i == 2 && value == store.before[i]) return false;
        store.fields[i] = value;
        if (!injected && i == 5 && value == store.after[i]) {
            injected = true;
            return false;
        }
        return true;
    };
    const auto result = store.run();
    require(result.status == WriteStatus::FieldWriteFailed,
            "original setter failure must remain visible");
    require(!result.rollbackVerified && store.fields != store.before,
            "failed restore must not report verified rollback");
    require(store.persists == 0, "failed rollback must not attempt persistence");
}

void restores_memory_after_persistence_failure() {
    Store store;
    store.onPersist = [] { return false; };
    const auto result = store.run();
    require(result.status == WriteStatus::PersistFailed,
            "persistence failure must be distinguished from field failure");
    require(result.persistenceAttempted && store.persists == 1,
            "failed persistence must be attempted exactly once");
    require(result.rollbackVerified && store.fields == store.before,
            "failed persistence should verify in-memory rollback");
    require(!store.persisted, "adapter must not claim successful persistence");
    store.expectReverseRollback(17);
}

void reports_post_persistence_mismatch_without_silent_rollback() {
    Store store;
    store.onPersist = [&] {
        store.fields[0] = 999;
        return true;
    };
    const auto result = store.run();
    require(result.status == WriteStatus::PostPersistMismatch,
            "post-persistence mismatch must not report a committed kit");
    require(result.persistenceAttempted && store.persists == 1,
            "post-persistence mismatch must retain persistence-attempt evidence");
    require(!result.rollbackVerified && store.writes.size() == 17,
            "post-persistence mismatch must not silently roll back only memory");
    require(store.fields[0] == 999, "observed post-persistence state must remain visible");
}

void reports_post_persistence_identity_loss() {
    Store store;
    store.onIdentity = [&] { return !store.persisted; };
    const auto result = store.run();
    require(result.status == WriteStatus::PostPersistMismatch,
            "post-persistence identity loss must prevent a success report");
    require(result.persistenceAttempted && store.persists == 1,
            "identity loss must not cause a second persistence attempt");
    require(!result.rollbackVerified && store.writes.size() == 17,
            "post-persistence identity loss must not silently roll back memory");
}

void creates_entry_with_weapon_identity_last() {
    Store store;
    // Variant index, sort index, eight attachments, eight looks, camo and
    // weaponIndex: the adapter provides identity last, as the DLL does.
    store.before = {7, 0};
    store.after = {7, 1};
    for (std::uint32_t i = 0; i < 8; ++i) {
        store.before.push_back(0);
        store.after.push_back(i + 21);
    }
    for (int i = 0; i < 8; ++i) {
        store.before.push_back(0);
        store.after.push_back(0);
    }
    store.before.push_back(0);
    store.after.push_back(101);
    store.before.push_back(0);
    store.after.push_back(48);
    store.fields = store.before;
    store.onWrite = [&](std::size_t i, std::uint32_t value) {
        if (i != 19) require(store.fields[19] == 0,
                            "entry must stay unoccupied until other fields are initialized");
        store.fields[i] = value;
        return true;
    };
    const auto result = store.run();
    require(result.status == WriteStatus::Committed && result.attempted == 20,
            "complete new entry must commit all 20 supplied fields");
    require(store.writes.back().first == 19 && store.writes.back().second == 48,
            "weapon identity must be the final setter");
    require(store.fields == store.after && store.persists == 1,
            "new entry must preserve all attachments and camo on persistence");
}
} // namespace

int main() {
    const std::vector<std::pair<const char*, void (*)()>> tests = {
        {"eight attachments, cosmetics and camo", edits_eight_attachments_cosmetics_and_camo},
        {"stale snapshot", rejects_stale_snapshot_without_writes},
        {"invalid vector sizes", rejects_invalid_field_vector_sizes},
        {"initial offline/context guard", rejects_offline_guard_before_writing},
        {"setter mutates then fails", rolls_back_a_setter_that_mutates_then_fails},
        {"immediate readback mismatch", rolls_back_an_immediate_readback_mismatch},
        {"immediate read failure", rolls_back_an_immediate_read_failure},
        {"late clobber", detects_late_clobber_before_persisting},
        {"context lost during write", stops_when_context_guard_is_lost},
        {"kit identity changed", rolls_back_when_kit_identity_changes},
        {"failed rollback", reports_failed_rollback},
        {"persistence failure", restores_memory_after_persistence_failure},
        {"post-persistence mismatch", reports_post_persistence_mismatch_without_silent_rollback},
        {"post-persistence identity loss", reports_post_persistence_identity_loss},
        {"creation identity last", creates_entry_with_weapon_identity_last},
    };
    int failures = 0;
    for (const auto& test : tests) {
        try {
            test.second();
            std::cout << "PASS: " << test.first << '\n';
        } catch (const std::exception& error) {
            ++failures;
            std::cerr << "FAIL: " << test.first << ": " << error.what() << '\n';
        }
    }
    std::cout << tests.size() - failures << '/' << tests.size() << " transaction tests passed\n";
    return failures ? 1 : 0;
}

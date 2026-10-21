#include "../SourcePatches/NativeKitSlots.v36.h"

#include <array>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace {
void require(bool ok, const char* message) {
    if (!ok) throw std::runtime_error(message);
}
struct Slot {
    scropts::kits::SlotMetadata metadata;
    std::array<std::uint32_t, 8> attachments{};
    std::array<std::uint32_t, 8> looks{};
};
struct Inventory {
    std::vector<Slot> slots;
    int unreadableMetadata = -1;
    int unreadablePart = -1;
    explicit Inventory(int count = 50) : slots(static_cast<std::size_t>(count)) {
        for (int i = 0; i < count; ++i)
            slots[static_cast<std::size_t>(i)].metadata.variant = static_cast<std::uint32_t>(i);
    }
    scropts::kits::EmptySlotSearch find() const {
        return scropts::kits::FindEmptySlot(48,
            [&](int i) { return static_cast<std::size_t>(i) < slots.size(); },
            [&](int i, scropts::kits::SlotMetadata& metadata) {
                if (i == unreadableMetadata) return false;
                metadata = slots[static_cast<std::size_t>(i)].metadata;
                return true;
            },
            [&](int i, int part, std::uint32_t& id, std::uint32_t& look) {
                if (i == unreadablePart) return false;
                const auto& slot = slots[static_cast<std::size_t>(i)];
                id = slot.attachments[static_cast<std::size_t>(part)];
                look = slot.looks[static_cast<std::size_t>(part)];
                return true;
            });
    }
};
}

int main() {
    int cases = 0;
    try {
        {
            Inventory inventory;
            auto result = inventory.find();
            require(result.readable == 50 && result.cleanUnused == 50 && result.candidate == 0,
                    "complete empty inventory must select first clean slot");
            ++cases;
        }
        {
            Inventory inventory;
            inventory.slots[0].metadata.weapon = 25;
            require(inventory.find().candidate == 1, "occupied entry must never be reused");
            ++cases;
        }
        {
            Inventory inventory;
            inventory.slots[49].metadata.weapon = 48;
            auto result = inventory.find();
            require(result.candidate < 0 && result.matchingWeapons == 1,
                    "existing weapon at end of scan must prevent duplicate creation");
            ++cases;
        }
        {
            Inventory inventory;
            inventory.slots[2].metadata.weapon = inventory.slots[49].metadata.weapon = 48;
            require(inventory.find().candidate < 0, "ambiguous existing kits must block creation");
            ++cases;
        }
        {
            for (int count : {0, 49, 51, 160}) {
                Inventory inventory(count);
                require(inventory.find().candidate < 0, "schema must expose exactly 50 slots");
            }
            ++cases;
        }
        {
            Inventory inventory;
            inventory.slots[0].metadata.variant = 9;
            inventory.slots[1].metadata.sort = 1;
            inventory.slots[2].metadata.readOnly = 1;
            inventory.slots[3].metadata.camo = 101;
            inventory.slots[4].metadata.reticle = 1;
            require(inventory.find().candidate == 5, "all native metadata must match an unused entry");
            ++cases;
        }
        {
            Inventory inventory;
            inventory.slots[0].attachments[7] = 11;
            inventory.slots[1].looks[7] = 2;
            require(inventory.find().candidate == 2, "all eight attachments and cosmetics must be empty");
            ++cases;
        }
        {
            Inventory inventory;
            inventory.unreadableMetadata = 49;
            auto result = inventory.find();
            require(result.candidate < 0 && result.unreadableSlot == 49,
                    "early free slot must not hide later unreadable metadata");
            ++cases;
        }
        {
            Inventory inventory;
            inventory.unreadablePart = 49;
            auto result = inventory.find();
            require(result.candidate < 0 && result.unreadableSlot == 49,
                    "unreadable attachment fields must block allocation");
            ++cases;
        }
        {
            Inventory inventory;
            for (auto& slot : inventory.slots) slot.metadata.weapon = 25;
            require(inventory.find().candidate < 0, "full inventory must not overwrite a slot");
            ++cases;
        }
        {
            Inventory inventory;
            require(inventory.find().candidate == 0, "initial candidate must exist");
            inventory.slots[0].metadata.weapon = 25;
            require(inventory.find().candidate == 1, "fresh scan must observe a newly occupied candidate");
            inventory.slots[1].metadata.weapon = 48;
            require(inventory.find().candidate < 0, "second save must not allocate a second kit");
            ++cases;
        }
        std::cout << cases << " native slot allocation cases passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Slot allocation failure after " << cases << " cases: " << error.what() << '\n';
        return 1;
    }
}

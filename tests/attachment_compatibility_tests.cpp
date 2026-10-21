#include "../SourcePatches/AttachmentCompatibility.v36.h"
#include <iostream>
#include <stdexcept>

using namespace weapon_kits::compatibility;

static void Require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

int main() {
    int cases = 0;
    try {
        const std::vector<Definition> definitions = {
            {"suppressed", 11, {"grip", "reflex"}},
            {"grip", 8, {"suppressed", "reflex"}},
            {"reflex", 1, {"suppressed", "grip"}}
        };
        const std::vector<std::string> catalog = {"suppressed", "grip", "reflex"};
        {
            auto r = Inspect("control", catalog, {"suppressed"}, definitions);
            Require(!r.HasMetadataBlockers(), "Listed known attachment must pass metadata checks");
            Require(r.attachments[0].id == 11, "Global ID must be preserved");
            Require(r.gameplay == GameplayStatus::Unverified, "Metadata must not certify gameplay");
            ++cases;
        }
        {
            auto r = Inspect("candidate", {"grip"}, {"suppressed"}, definitions);
            Require(r.HasMetadataBlockers(), "A global Suppressor ID must not bypass catalog membership");
            Require(r.attachments[0].identity == IdentityStatus::Known, "Known global ID is separate evidence");
            Require(r.attachments[0].catalog == CatalogStatus::NotListed, "Unlisted status must be explicit");
            ++cases;
        }
        {
            auto r = Inspect("candidate", {"suppressed"}, {"suppressed"}, {});
            Require(r.attachments[0].identity == IdentityStatus::Missing, "UI fallback token cannot invent an ID");
            Require(r.HasMetadataBlockers(), "Missing global definition must block metadata check");
            ++cases;
        }
        {
            auto duplicated = definitions;
            duplicated.push_back({"suppressed", 99, {}});
            auto r = Inspect("candidate", catalog, {"suppressed"}, duplicated);
            Require(r.attachments[0].identity == IdentityStatus::Ambiguous, "Conflicting token definitions must be rejected");
            Require(r.HasMetadataBlockers(), "Ambiguous definitions must block");
            ++cases;
        }
        {
            auto aliased = definitions;
            aliased.push_back({"other", 11, {}});
            auto r = Inspect("candidate", catalog, {"suppressed"}, aliased);
            Require(r.attachments[0].identity == IdentityStatus::Ambiguous, "Shared ID must not identify two tokens");
            ++cases;
        }
        {
            for (std::uint32_t id : {0u, 255u, 4294967295u}) {
                auto r = Inspect("candidate", catalog, {"suppressed"}, {{"suppressed", id, {}}});
                Require(r.attachments[0].identity == IdentityStatus::Invalid, "Out-of-range global ID must fail");
                Require(r.HasMetadataBlockers(), "Invalid global ID must block");
            }
            ++cases;
        }
        {
            auto r = Inspect("candidate", catalog, {"suppressed", "suppressed", "suppressed"}, definitions);
            Require(r.attachments.size() == 1 && r.duplicateSelections.size() == 1, "Duplicates must be reported once");
            Require(r.HasMetadataBlockers(), "Duplicate selections must fail preflight");
            ++cases;
        }
        {
            auto r = Inspect("control", catalog, {"suppressed", "grip", "reflex"}, definitions);
            Require(r.pairs.size() == 3, "Every unique selected pair must be checked");
            Require(!r.HasMetadataBlockers(), "Bidirectionally compatible pairs must pass metadata checks");
            ++cases;
        }
        {
            auto asymmetric = definitions;
            asymmetric[1].compatibleWith.clear();
            auto r = Inspect("candidate", catalog, {"suppressed", "grip"}, asymmetric);
            Require(r.pairs[0].firstAllowsSecond == PairStatus::Permitted, "Forward pair evidence must be preserved");
            Require(r.pairs[0].secondAllowsFirst == PairStatus::Conflict, "Reverse pair conflict must be found");
            Require(r.HasMetadataBlockers(), "Asymmetric pair must block");
            ++cases;
        }
        {
            auto r = Inspect("candidate", catalog, {"suppressed", "missing"}, definitions);
            Require(r.pairs[0].firstAllowsSecond == PairStatus::Unknown &&
                    r.pairs[0].secondAllowsFirst == PairStatus::Unknown,
                    "Missing definition must not fabricate pair evidence");
            Require(r.HasMetadataBlockers(), "Unknown pairs must block");
            ++cases;
        }
        {
            auto r = Inspect("control", catalog, {}, definitions);
            Require(r.attachments.empty() && r.pairs.empty(), "Empty selection must produce no invented attachment");
            Require(!r.HasMetadataBlockers(), "Empty selection must not prohibit camo-only edits");
            Require(r.gameplay == GameplayStatus::Unverified, "No runtime checks were performed even for empty selection");
            ++cases;
        }
        {
            auto r = Inspect("candidate", {"not_suppressed"}, {"suppressed"}, definitions);
            Require(r.attachments[0].catalog == CatalogStatus::NotListed, "Catalog matching must use exact tokens");
            Require(SplitTokens("grip\treflex\n suppressed ") ==
                    std::vector<std::string>({"grip", "reflex", "suppressed"}), "Whitespace tokens must parse exactly");
            ++cases;
        }
        {
            auto r = Inspect("candidate", {"grip"}, {"suppressed"}, definitions);
            const auto text = FormatReport(r);
            Require(text.find("NOT LISTED; global ID=11") != std::string::npos,
                    "Report must distinguish catalog absence from a known numeric ID");
            Require(text.find("Gameplay compatibility: UNVERIFIED") != std::string::npos,
                    "Report must not misrepresent metadata as gameplay proof");
            Require(text.find("cannot authorize a native write") != std::string::npos,
                    "Diagnostic report must not provide a safety bypass");
            ++cases;
        }
        std::cout << cases << " attachment compatibility cases passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Attachment compatibility failure after " << cases << " passed cases: " << error.what() << '\n';
        return 1;
    }
}

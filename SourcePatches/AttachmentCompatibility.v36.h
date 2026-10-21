#pragma once

#include <algorithm>
#include <cstdint>
#include <sstream>
#include <string>
#include <vector>

// Read-only evidence from BO3's loaded catalogs. This module does not resolve
// weapon assets, grant an unsupported-attachment override, or write native DDL.
namespace weapon_kits {
namespace compatibility {

struct Definition {
    std::string token;
    std::uint32_t id = 0;
    std::vector<std::string> compatibleWith;
};

enum class CatalogStatus { Listed, NotListed };
enum class IdentityStatus { Known, Missing, Invalid, Ambiguous };
enum class PairStatus { Permitted, Conflict, Unknown };
enum class GameplayStatus { Unverified };

struct AttachmentFinding {
    std::string token;
    CatalogStatus catalog = CatalogStatus::NotListed;
    IdentityStatus identity = IdentityStatus::Missing;
    std::uint32_t id = 0;
};

struct PairFinding {
    std::string first;
    std::string second;
    PairStatus firstAllowsSecond = PairStatus::Unknown;
    PairStatus secondAllowsFirst = PairStatus::Unknown;
};

struct Report {
    std::string weapon;
    std::vector<AttachmentFinding> attachments;
    std::vector<PairFinding> pairs;
    std::vector<std::string> duplicateSelections;
    GameplayStatus gameplay = GameplayStatus::Unverified;

    // This describes only the supplied metadata. Passing never implies that a
    // write is safe: the existing writer owns all schema/slot/session checks.
    bool HasMetadataBlockers() const {
        if (!duplicateSelections.empty()) return true;
        for (const auto& attachment : attachments) {
            if (attachment.catalog != CatalogStatus::Listed ||
                attachment.identity != IdentityStatus::Known) return true;
        }
        for (const auto& pair : pairs) {
            if (pair.firstAllowsSecond != PairStatus::Permitted ||
                pair.secondAllowsFirst != PairStatus::Permitted) return true;
        }
        return false;
    }
};

inline bool Contains(const std::vector<std::string>& values, const std::string& value) {
    return std::find(values.begin(), values.end(), value) != values.end();
}

inline std::vector<std::string> SplitTokens(const std::string& words) {
    std::vector<std::string> result;
    std::istringstream input(words);
    std::string word;
    while (input >> word) result.push_back(word);
    return result;
}

// Supply every readable global attachment definition when possible. A subset
// cannot reveal ID aliases in omitted rows; no completeness claim is made here.
inline Report Inspect(const std::string& weapon,
                      const std::vector<std::string>& weaponCatalog,
                      const std::vector<std::string>& selected,
                      const std::vector<Definition>& definitions) {
    Report report;
    report.weapon = weapon;
    std::vector<const Definition*> resolved;
    for (const auto& token : selected) {
        const auto existing = std::find_if(report.attachments.begin(), report.attachments.end(),
            [&token](const AttachmentFinding& finding) { return finding.token == token; });
        if (existing != report.attachments.end()) {
            if (!Contains(report.duplicateSelections, token)) report.duplicateSelections.push_back(token);
            continue;
        }
        AttachmentFinding finding;
        finding.token = token;
        finding.catalog = Contains(weaponCatalog, token) ? CatalogStatus::Listed : CatalogStatus::NotListed;
        const Definition* definition = nullptr;
        std::size_t matches = 0;
        for (const auto& candidate : definitions) {
            if (candidate.token == token) {
                definition = &candidate;
                ++matches;
            }
        }
        if (matches > 1) {
            finding.identity = IdentityStatus::Ambiguous;
        } else if (definition) {
            finding.id = definition->id;
            if (definition->id < 1 || definition->id > 254) {
                finding.identity = IdentityStatus::Invalid;
            } else {
                finding.identity = IdentityStatus::Known;
                for (const auto& candidate : definitions) {
                    if (candidate.id == definition->id && candidate.token != token) {
                        finding.identity = IdentityStatus::Ambiguous;
                        break;
                    }
                }
            }
        }
        report.attachments.push_back(finding);
        resolved.push_back(finding.identity == IdentityStatus::Known ? definition : nullptr);
    }
    for (std::size_t i = 0; i < report.attachments.size(); ++i) {
        for (std::size_t j = i + 1; j < report.attachments.size(); ++j) {
            PairFinding pair;
            pair.first = report.attachments[i].token;
            pair.second = report.attachments[j].token;
            if (resolved[i] && resolved[j]) {
                pair.firstAllowsSecond = Contains(resolved[i]->compatibleWith, pair.second)
                    ? PairStatus::Permitted : PairStatus::Conflict;
                pair.secondAllowsFirst = Contains(resolved[j]->compatibleWith, pair.first)
                    ? PairStatus::Permitted : PairStatus::Conflict;
            }
            report.pairs.push_back(pair);
        }
    }
    return report;
}

inline const char* Describe(PairStatus status) {
    switch (status) {
    case PairStatus::Permitted: return "permitted";
    case PairStatus::Conflict: return "not permitted";
    default: return "unknown";
    }
}

inline std::string FormatReport(const Report& report) {
    std::ostringstream out;
    out << "Weapon: " << report.weapon << "\nAttachment catalog evidence:\n";
    if (report.attachments.empty()) out << "  No attachments selected.\n";
    for (const auto& attachment : report.attachments) {
        out << "  " << attachment.token << ": Zombies catalog="
            << (attachment.catalog == CatalogStatus::Listed ? "listed" : "NOT LISTED")
            << "; global ID=";
        switch (attachment.identity) {
        case IdentityStatus::Known: out << attachment.id; break;
        case IdentityStatus::Missing: out << "UNKNOWN (no readable definition)"; break;
        case IdentityStatus::Invalid: out << "INVALID (" << attachment.id << ")"; break;
        case IdentityStatus::Ambiguous: out << "AMBIGUOUS (duplicate token or shared ID)"; break;
        }
        out << '\n';
    }
    for (const auto& duplicate : report.duplicateSelections)
        out << "  Duplicate selection: " << duplicate << '\n';
    for (const auto& pair : report.pairs) {
        out << "  Pair " << pair.first << " -> " << pair.second << ": "
            << Describe(pair.firstAllowsSecond) << "; " << pair.second << " -> " << pair.first
            << ": " << Describe(pair.secondAllowsFirst) << '\n';
    }
    out << "Supplied catalog/ID/pair metadata: "
        << (report.HasMetadataBlockers() ? "BLOCKED" : "checks passed") << ".\n"
        << "Gameplay compatibility: UNVERIFIED. Catalogs and saved IDs do not prove loaded assets, "
        << "sound, muzzle effects or firing behavior.\n"
        << "This report cannot authorize a native write or override the writer's safety checks.";
    return out.str();
}

} // namespace compatibility
} // namespace weapon_kits

// FuzzyMatch.swift — Fast fuzzy matching with scoring
//
// Sequential character matching (like fzf): every query character must appear
// in order in the target, but gaps are allowed. The score reflects match quality:
//   - Word boundary matches ("vsc" → "Visual Studio Code") score highest
//   - Consecutive runs ("calc" → "Calculator") score well
//   - Scattered matches ("fx" → "Firefox") score lower but still match
//
// O(n) per candidate — trivially fast for ~200 apps on every keystroke.

import Foundation

struct FuzzyResult {
    let matched: Bool
    let score: Int
}

func fuzzyMatch(query: String, target: String) -> FuzzyResult {
    let queryChars = Array(query.lowercased())
    let targetChars = Array(target.lowercased())

    guard !queryChars.isEmpty else { return FuzzyResult(matched: true, score: 0) }

    // Phase 1: find a valid subsequence match and record positions
    var matchPositions: [Int] = []
    var qi = 0

    for ti in 0..<targetChars.count {
        if qi < queryChars.count && queryChars[qi] == targetChars[ti] {
            matchPositions.append(ti)
            qi += 1
        }
    }

    guard qi == queryChars.count else {
        return FuzzyResult(matched: false, score: 0)
    }

    // Phase 2: score the match
    var score = 100

    // Bonus: match starts at beginning of string
    if matchPositions[0] == 0 {
        score += 15
    }

    // Bonus: the entire query is a contiguous prefix of the target
    // ("to" -> "Tolaria"). This is by far the strongest user signal —
    // somebody typing the first letters of an app name almost always
    // wants that exact app, even when a heavily-used app contains the
    // same letters scattered (e.g. "to" -> "Stremio"). Big enough to
    // beat the frecency boost on long-tail apps without overwhelming
    // genuine ties.
    let qLower = query.lowercased()
    let tLower = target.lowercased()
    if tLower.hasPrefix(qLower) {
        score += 60
    }

    // Bonus: word boundary matches (char preceded by space/dash/underscore or camelCase)
    let originalChars = Array(target)
    var boundaryCount = 0
    for pos in matchPositions {
        if pos == 0 {
            boundaryCount += 1
        } else if isBoundary(prev: originalChars[pos - 1], curr: originalChars[pos]) {
            boundaryCount += 1
        }
    }
    score += boundaryCount * 10

    // Bonus: full acronym match (every query char hits a boundary)
    if boundaryCount == queryChars.count {
        score += 20
    }

    // Bonus: longest consecutive run
    var maxRun = 1
    var currentRun = 1
    for i in 1..<matchPositions.count {
        if matchPositions[i] == matchPositions[i - 1] + 1 {
            currentRun += 1
            maxRun = max(maxRun, currentRun)
        } else {
            currentRun = 1
        }
    }
    score += maxRun * 8

    // Bonus: prefer shorter targets ("Vim" over "Visual Studio Code Vim Plugin")
    score += max(0, 50 - targetChars.count)

    // Penalty: leading gap (match starts deep in the string)
    score -= matchPositions[0] * 2

    // Penalty: total gaps between matches
    let totalGap = matchPositions.last! - matchPositions.first! - (matchPositions.count - 1)
    score -= totalGap

    return FuzzyResult(matched: true, score: max(0, score))
}

private func isBoundary(prev: Character, curr: Character) -> Bool {
    if prev == " " || prev == "-" || prev == "_" || prev == "." || prev == "/" {
        return true
    }
    // camelCase boundary: lowercase followed by uppercase
    if prev.isLowercase && curr.isUppercase {
        return true
    }
    return false
}

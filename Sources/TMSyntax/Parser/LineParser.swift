import Foundation

internal final class LineParser {
    public init(line: String,
                matchStack: MatchStateStack)
    {
        self.line = line
        self.lineEndPosition = line.lineEndIndex
        self.position = line.startIndex
        self.matchStack = matchStack
        self.tokens = []
    }

    private let line: String
    private let lineEndPosition: String.Index
    private var position: String.Index
    private var matchStack: MatchStateStack
    private var tokens: [Token]
    
    private var currentRule: Rule {
        return matchStack.top!.rule
    }
    private var currentScopes: [ScopeName] {
        return matchStack.items.compactMap { $0.scopeName }
    }

    public func parse() throws -> Parser.Result {
        while true {
            let matchPlans = collectMatchPlans()
            
            let positionInByte = line.utf8.distance(from: line.startIndex, to: position)
            
            trace("--- match plans \(matchPlans.count), position \(positionInByte) ---")
            for plan in matchPlans {
                trace("\(plan)")
            }
            trace("------")
            
            guard let result = try search(line: line,
                                          start: position,
                                          plans: matchPlans) else
            {
                trace("no match, end line")
                
                extendOuterScope(end: lineEndPosition)
                
                break
            }
            
            processMatchResult(result)
        }
        
        return Parser.Result(matchStack: matchStack, tokens: tokens)
    }
    
    private func collectMatchPlans() -> [MatchPlan] {
        var plans: [MatchPlan] = []
        
        switch currentRule.switcher {
        case .include,
             .match:
            break
        case .scope(let rule):
            switch rule.condition {
            case .beginEnd(let cond):
                let endPlan = MatchPlan.endRule(rule, cond)
                plans.append(endPlan)
            case .none:
                break
            }
            
            for e in rule.patterns {
                plans += e.collectEnterMatchPlans()
            }
        }
        
        return plans
    }
    
    private func search(line: String, start: String.Index, plans: [MatchPlan]) throws -> MatchResult? {
        var matchResults: [(Int, MatchResult)] = []
        
        for (index, plan) in plans.enumerated() {
            let regex = try plan.regexPattern.compile()
            if let match = regex.search(string: line, range: start..<lineEndPosition) {
                matchResults.append((index, MatchResult(plan: plan, match: match)))
            }
        }
        
        matchResults.sort { (a, b) -> Bool in
            let (ai, am) = a
            let (bi, bm) = b
            
            if am.match[0].lowerBound != bm.match[0].lowerBound {
                return am.match[0].lowerBound < bm.match[0].lowerBound
            }
            
            return ai < bi
        }
        
        guard let best = matchResults.first else {
            return nil
        }
        
        return best.1
    }
    
    private func processMatchResult(_ result: MatchResult) {
        trace("match!: \(result.plan)")
        
        let newPosition = result.match[0].upperBound
        
        extendOuterScope(end: result.match[0].lowerBound)
        
        switch result.plan {
        case .matchRule(let rule):
            let newState = MatchState(rule: rule, scopeName: rule.scopeName)
            matchStack.push(newState)
            buildCaptureTokens(result: result, captures: rule.captures)
            matchStack.pop()
        case .beginRule(let rule, let cond):
            let newState = MatchState(rule: rule, scopeName: rule.scopeName)
            matchStack.push(newState)
            buildCaptureTokens(result: result, captures: cond.beginCaptures)    
        case .endRule(let rule, let cond):
            _ = rule
            buildCaptureTokens(result: result, captures: cond.endCaptures)
            matchStack.pop()
        }
        
        position = newPosition
    }
    
    private func buildCaptureTokens(result: MatchResult,
                                    captures: CaptureAttributes?) {
        let accum = ScopeAccumulator()
        
        var currentScopes = self.currentScopes
    
        let bottomScope = currentScopes.last!
        currentScopes.removeLast()
        
        accum.items.append(ScopeAccumulator.Item(range: result.match[0],
                                                 scope: bottomScope))
        
        if let captures = captures {
            for (key, attr) in captures.dictionary {
                guard let captureIndex = Int(key),
                    captureIndex < result.match.ranges.count else
                {
                    continue
                }
                
                accum.items.append(ScopeAccumulator.Item(range: result.match[captureIndex],
                                                         scope: attr.name))
            }
        }
        
        let tokens = accum.buildTokens()
        for var token in tokens {
            token.scopes = currentScopes + token.scopes
            addToken(token)
        }
    }
    
    private func extendOuterScope(end: String.Index) {
        guard position < end else {
            return
        }
        
        let token = Token(range: position..<end,
                          scopes: currentScopes)
        addToken(token)
    }
    
    private func addToken(_ token: Token) {
        tokens.append(token)
    }
    
    private func trace(_ string: String) {
        print("[Parser trace] \(string)")
    }

}

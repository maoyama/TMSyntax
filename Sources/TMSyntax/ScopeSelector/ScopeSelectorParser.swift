import Foundation

public final class ScopeSelectorParser {
    public enum Error : LocalizedError {
        case syntaxError
        
        public var errorDescription: String? {
            switch self {
            case .syntaxError: return "syntax error"
            }
        }
    }
    
    private let source: String
    private let nameMatcher: ScopeNameMatcher

    private let tokenRegex: Regex
    private var position: String.Index
    private var token: Token
    
    private enum Token : Equatable {
        case leftPosition
        case rightPosition
        case comma
        case pipe
        case minus
        case leftParen
        case rightParen
        case name(ScopeName)
        case end
    }
    
    public init(source: String,
                nameMatcher: @escaping ScopeNameMatcher)
    {
        self.source = source
        self.nameMatcher = nameMatcher
        
        let pattern = "([LR]:|[bwb.b-]+|[b,b|b-b(b)])".replacingOccurrences(of: "b", with: "\\")
        
        self.tokenRegex = try! Regex(pattern: pattern, options: [])
        self.position = source.startIndex
        self.token = .end
        
        readToken()
    }
    
    public func parse() throws -> ScopeSelector {
        var pes: [ScopePositionalMatchExpression] = []
        while true {
            if token == .end {
                break
            }
            
            var position: ScopeMatchPosition = .none
            if token == .leftPosition {
                position = .left
                readToken()
            } else if token == .rightPosition {
                position = .right
                readToken()
            }
            
            let expression = try parseConjunction()
            
            let pe = ScopePositionalMatchExpression(position: position,
                                                    expression: expression)
            pes.append(pe)
            
            if token == .comma {
                readToken()
                continue
            }
            
            break
        }
        return ScopeSelector(expressions: pes)
    }
    
    private func parseConjunction() throws -> ScopeMatchConjunctionExpression {
        var es: [ScopeMatchExpression] = []
        while true {
            guard let e = try tryParseExpression() else {
                break
            }
            es.append(e)
        }
        return ScopeMatchConjunctionExpression(expressions: es)
    }
    
    private func parseDisjunction() throws -> ScopeMatchDisjunctionExpression {
        var es: [ScopeMatchExpression] = []
        while true {
            guard let e = try tryParseExpression() else {
                break
            }
            es.append(e)
            
            if token == .comma || token == .pipe {
                readToken()
                continue
            }
            break
        }
        return ScopeMatchDisjunctionExpression(expressions: es)
    }
    
    private func tryParseExpression() throws -> ScopeMatchExpression? {
        switch token {
        case .minus:
            readToken()
            guard let e = try tryParseExpression() else {
                throw Error.syntaxError
            }
            return ScopeMatchNegationExpression(expression: e)
        case .leftParen:
            readToken()
            let e = try parseDisjunction()
            guard token == .rightParen else {
                throw Error.syntaxError
            }
            readToken()
            return e
        case .name(let name):
            readToken()
            return ScopeMatchNameExpression(pattern: name,
                                            matcher: nameMatcher)
        default:
            return nil
        }
    }
    
    private func readToken() {
        self.token = _readToken()
    }
    
    private func _readToken() -> Token {
        guard let match = tokenRegex.search(string: source,
                                            range: position..<source.endIndex) else
        {
            return .end
        }
        
        let s = String(source[match[]])
        position = match[].upperBound
        
        switch s {
        case "L:": return .leftPosition
        case "R:": return .rightPosition
        case ",": return .comma
        case "|": return .pipe
        case "-": return .minus
        case "(": return .leftParen
        case ")": return .rightParen
        default: return .name(ScopeName(s))
        }
    }
    
    
}

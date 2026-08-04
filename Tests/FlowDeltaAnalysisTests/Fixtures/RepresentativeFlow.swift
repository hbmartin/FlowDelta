func route(_ values: [Int], enabled: Bool) throws -> Int {
    defer { audit(values.count) }
    guard enabled else { return 0 }

    var total = 0
    for value in values {
        if value < 0 {
            continue
        } else if value == 0 {
            break
        }

        switch value {
        case 1:
            total += 1
        case 2...10:
            total += try normalize(value)
        default:
            throw RouteError.unsupported
        }
    }

    repeat {
        total -= 1
    } while total > 100

    do {
        try persist(total)
    } catch {
        return -1
    }
    return total
}

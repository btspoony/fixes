import "FRC20Indexer"

pub fun main(
    partial: Bool,
    chooseCompleted: Bool,
): [FRC20Info] {
    let indexer = FRC20Indexer.getIndexer()
    let tokens = indexer.getTokens()

    let ret: [FRC20Info] = []
    for tick in tokens {
        if let meta = indexer.getTokenMeta(tick: tick) {
            let isCompleted = meta.max == meta.supplied
            if partial {
                if chooseCompleted && !isCompleted {
                    continue
                } else if !chooseCompleted && isCompleted {
                    continue
                }
            }
            ret.append(FRC20Info(
                meta: meta,
                holders: indexer.getHoldersAmount(tick: tick),
                pool: indexer.getPoolBalance(tick: tick),
            ))
        }
    }
    return ret
}

pub struct FRC20Info {
    pub let holders: UInt64
    pub let meta: FRC20Indexer.FRC20Meta
    pub let pool: UFix64

    init(
        meta: FRC20Indexer.FRC20Meta,
        holders: UInt64,
        pool: UFix64,
    ) {
        self.holders = holders
        self.meta = meta
        self.pool = pool
    }
}

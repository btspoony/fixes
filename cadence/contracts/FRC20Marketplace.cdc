// Third-party imports
import "StringUtils"
import "MetadataViews"
import "FungibleTokenMetadataViews"
import "FlowToken"
// Fixes imports
import "FRC20FTShared"
import "FRC20Indexer"
import "FRC20Storefront"
import "FRC20AccountsPool"

pub contract FRC20Marketplace {

    /* --- Events --- */
    /// Event emitted when the contract is initialized
    pub event ContractInitialized()

    /// Event emitted when a new market is created
    pub event MarketCreated(tick: String, uuid: UInt64)
    /// Event emitted when a new listing is added
    pub event ListingAdded(tick: String, storefront: Address, listingId: UInt64, type: UInt8)
    /// Event emitted when a listing is removed
    pub event ListingRemoved(tick: String, storefront: Address, listingId: UInt64, type: UInt8)

    /// Event emitted when the market is accessable
    pub event MarketWhitelistClaimed(tick: String, addr: Address)

    /* --- Variable, Enums and Structs --- */

    pub let FRC20MarketStoragePath: StoragePath
    pub let FRC20MarketPublicPath: PublicPath

    /* --- Interfaces & Resources --- */
    /// The Listing item information
    pub struct ListedItem {
        // The combined uid for querying in the market
        pub let rankedId: String
        // The address of the storefront
        pub let storefront: Address
        // The listing resource uuid
        pub let id: UInt64
        // The timestamp when the listing was added
        pub let timestamp: UFix64

        init(address: Address, listingID: UInt64) {
            let storefront = FRC20Storefront.borrowStorefront(address: address)
                ?? panic("no storefront found in address:".concat(address.toString()))
            self.storefront = address
            self.id = listingID
            let listingRef = storefront.borrowListing(listingID)
                ?? panic("no listing id found in storefront:".concat(address.toString()))
            self.timestamp = getCurrentBlock().timestamp
            let details = listingRef.getDetails()
            // combine the price rank and listing id
            self.rankedId = details.type.rawValue.toString()
                .concat("-")
                .concat(details.priceRank().toString())
                .concat("-")
                .concat(listingID.toString())
        }

        /// Get the listing details
        access(all) view
        fun getDetails(): FRC20Storefront.ListingDetails? {
            let listingRef = self.borrowListing()
            return listingRef?.getDetails()
        }

        /// Borrow the listing resource
        access(all) view
        fun borrowListing(): &FRC20Storefront.Listing{FRC20Storefront.ListingPublic}? {
            if let storefront = self.borrowStorefront() {
                return storefront.borrowListing(self.id)
            }
            return nil
        }

        /// Borrow the storefront resource
        access(all) view
        fun borrowStorefront(): &FRC20Storefront.Storefront{FRC20Storefront.StorefrontPublic}? {
            return FRC20Storefront.borrowStorefront(address: self.storefront)
        }
    }

    /// The Item identifier in the market
    ///
    pub struct ItemIdentifier {
        access(all)
        let type: FRC20Storefront.ListingType
        access(all)
        let rank: UInt64
        access(all)
        let listingId: UInt64

        init(type: FRC20Storefront.ListingType, rank: UInt64, listingId: UInt64) {
            self.type = type
            self.rank = rank
            self.listingId = listingId
        }
    }

    /// The Listing collection public interface
    ///
    pub resource interface ListingCollectionPublic {
        access(all)
        fun getListedIds(): [UInt64]
        access(all)
        fun getListedItem(_ id: UInt64): ListedItem?
    }

    /// The Listing collection
    ///
    pub resource ListingCollection: ListingCollectionPublic {
        // Listing ID => ListedItem
        access(contract)
        let listingIDItems: {UInt64: ListedItem}

        init() {
            self.listingIDItems = {}
        }

        // Public methods

        access(all)
        fun getListedIds(): [UInt64] {
            return self.listingIDItems.keys
        }

        access(all)
        fun getListedItem(_ id: UInt64): ListedItem? {
            return self.listingIDItems[id]
        }

        // Internal methods

        access(contract)
        fun borrowListedItem(_ id: UInt64): &ListedItem? {
            return &self.listingIDItems[id] as &ListedItem?
        }

        access(contract)
        fun addListedItem(_ listedItem: ListedItem) {
            self.listingIDItems[listedItem.id] = listedItem
        }

        access(contract)
        fun removeListedItem(_ id: UInt64) {
            self.listingIDItems.remove(key: id)
        }
    }

    /// Market public interface
    ///
    pub resource interface MarketPublic {
        /// The ticker name of the FRC20 market
        access(all) view
        fun getTickerName(): String

        access(all) view
        fun getPriceRanks(type: FRC20Storefront.ListingType): [UInt64]

        access(all) view
        fun getListedIds(type: FRC20Storefront.ListingType, rank: UInt64): [UInt64]

        access(all) view
        fun getListedItem(type: FRC20Storefront.ListingType, rank: UInt64, id: UInt64): ListedItem?

        /// Get the listing item
        access(all) view
        fun getListedItemByRankdedId(rankedId: String): ListedItem?

        // ---- Market operations ----

        /// Add a listing to the market
        access(all)
        fun addToList(storefront: Address, listingId: UInt64)

        // Anyone can remove it if the listing item has been removed or purchased.
        access(all)
        fun removeCompletedListing(rankedId: String)

        // ---- Accessable settings ----

        /// Check if the market is accessable
        access(all) view
        fun isAccessable(): Bool

        /// The accessable after timestamp
        access(all) view
        fun accessableAfter(): UInt64?

        /// The accessable conditions: tick => amount, the conditions are OR relationship
        access(all) view
        fun whitelistClaimingConditions(): {String: UFix64}

        access(all) view
        fun isInWhitelist(addr: Address): Bool

        // Claim the address to the whitelist before the accessable timestamp
        access(all)
        fun claimWhitelist(addr: Address)
    }

    /// The Market resource
    ///
    pub resource Market: MarketPublic {
        access(contract)
        let tick:String
        access(self)
        let collections: @{FRC20Storefront.ListingType: {UInt64: ListingCollection}}
        access(self)
        let sortedPriceRanks: {FRC20Storefront.ListingType: [UInt64]}
        access(self)
        let accessWhitelist: {Address: Bool}

        init(
            tick: String
        ) {
            self.tick = tick
            self.collections <- {}
            self.sortedPriceRanks = {}
            self.accessWhitelist = {}
        }

        destroy() {
            destroy self.collections
        }

        /** ---- Public Methods ---- */

        /// The ticker name of the FRC20 market
        ///
        access(all) view
        fun getTickerName(): String {
            return self.tick
        }

        /// Get the price ranks
        ///
        access(all) view
        fun getPriceRanks(type: FRC20Storefront.ListingType): [UInt64] {
            return self.sortedPriceRanks[type] ?? []
        }

        /// Get the listed ids
        ///
        access(all) view
        fun getListedIds(type: FRC20Storefront.ListingType, rank: UInt64): [UInt64] {
            let colRef = self.borrowCollection(type, rank)
            return colRef?.getListedIds() ?? []
        }

        /// Get the listing item
        ///
        access(all) view
        fun getListedItem(type: FRC20Storefront.ListingType, rank: UInt64, id: UInt64): ListedItem? {
            if let colRef = self.borrowCollection(type, rank) {
                return colRef.getListedItem(id)
            }
            return nil
        }

        /// Get the listing item
        ///
        access(all) view
        fun getListedItemByRankdedId(rankedId: String): ListedItem? {
            let ret = self.parseRankedId(rankedId: rankedId)
            return self.getListedItem(type: ret.type, rank: ret.rank, id: ret.listingId)
        }

        /// Add a listing to the market
        access(all)
        fun addToList(storefront: Address, listingId: UInt64) {
            let item = ListedItem(address: storefront, listingID: listingId)
            let listingRef = item.borrowListing()
                ?? panic("no listing id found in storefront:".concat(storefront.toString()))
            let details = listingRef.getDetails()
            /// The listing item must be available
            assert(
                details.status == FRC20Storefront.ListingStatus.Available,
                message: "The listing is not active"
            )
            /// The tick should be the same as the market's ticker name
            assert(
                details.tick == self.tick,
                message: "The listing tick is not the same as the market's ticker name"
            )

            let rank = details.priceRank()
            let collRef = self.borrowOrCreateCollection(details.type, rank)
            collRef.addListedItem(item)

            // update the sorted price ranks
            let ranks = self.getPriceRanks(type: details.type)
            // add the rank if it's not in the list
            if !ranks.contains(rank) {
                var idx: Int = -1
                // Find the right index to insert, rank should be in ascending order
                for i, curr in ranks {
                    if curr > rank {
                        idx = i
                        break
                    }
                }
                if idx == -1 {
                    // append to the end
                    ranks.append(rank)
                } else {
                    // insert at the right index
                    ranks.insert(at: idx, rank)
                }
                // update the sorted price ranks
                self.sortedPriceRanks[details.type] = ranks
            }
            // emit event
            emit ListingAdded(tick: self.tick, storefront: storefront, listingId: listingId, type: details.type.rawValue)
        }

        // Anyone can remove it if the listing item has been removed or purchased.
        access(all)
        fun removeCompletedListing(rankedId: String) {
            let parsed = self.parseRankedId(rankedId: rankedId)
            if let collRef = self.borrowCollection(parsed.type, parsed.rank) {
                if let listedItemRef = collRef.borrowListedItem(parsed.listingId) {
                    let listingRef = listedItemRef.borrowListing()
                    if listingRef == nil {
                        // remove the listed item if the listing resource is not found
                        collRef.removeListedItem(parsed.listingId)
                    } else {
                        let details = listingRef!.getDetails()
                        assert(
                            details.isCancelled() || details.isCompleted(),
                            message: "The listing is not cancelled or completed"
                        )
                        // remove the listed item if the listing is cancelled or completed
                        collRef.removeListedItem(parsed.listingId)
                    }
                    // emit event
                    emit ListingRemoved(tick: self.tick, storefront: listedItemRef.storefront, listingId: parsed.listingId, type: parsed.type.rawValue)
                }
            }
        }

        // ---- Accessable settings ----

        /// Check if the market is accessable
        ///
        access(all) view
        fun isAccessable(): Bool {
            if let after = self.accessableAfter() {
                return UInt64(getCurrentBlock().timestamp) >= after
            }
            return true
        }

        /// The accessable after timestamp
        ///
        access(all) view
        fun accessableAfter(): UInt64? {
            if let storeRef = self.borrowSharedStore() {
                return storeRef.get("market:AccessableAfter") as! UInt64?
            }
            return nil
        }

        /// The accessable conditions: tick => amount, the conditions are OR relationship
        ///
        access(all) view
        fun whitelistClaimingConditions(): {String: UFix64} {
            let ret: {String: UFix64} = {}
            if let storeRef = self.borrowSharedStore() {
                let name = storeRef.get("market:whitelistClaimingTickName") as! String?
                let amt = storeRef.get("market:whitelistClaimingTickAmount") as! UFix64?
                if name != nil && amt != nil {
                    ret[name!] = amt
                }
            }
            return ret
        }

        /// Check if the address is in the whitelist
        ///
        access(all) view
        fun isInWhitelist(addr: Address): Bool {
            return self.accessWhitelist[addr] ?? false
        }

        /// Claim the address to the whitelist before the accessable timestamp
        ///
        access(all)
        fun claimWhitelist(addr: Address) {
            let isAccessableNow = self.isAccessable()
            if isAccessableNow {
                return
            }

            let conds = self.whitelistClaimingConditions()
            if conds.keys.length == 0 {
                return
            }

            let frc20Indexer = FRC20Indexer.getIndexer()
            var valid = false
            for tick in conds.keys {
                let balance = frc20Indexer.getBalance(tick: tick, addr: addr)
                if balance >= conds[tick]! {
                    valid = true
                    break
                }
            }

            // add to the whitelist if valid
            if valid {
                self.accessWhitelist[addr] = true

                emit MarketWhitelistClaimed(tick: self.tick, addr: addr)
            }
        }

        /** ---- Internal Methods ---- */

        /// Borrow the shared store
        ///
        access(self)
        fun borrowSharedStore(): &FRC20FTShared.SharedStore{FRC20FTShared.SharedStorePublic}? {
            return FRC20FTShared.borrowStoreRef(self.owner!.address)
        }

        /// Parse the ranked id
        ///
        access(self) view
        fun parseRankedId(rankedId: String): ItemIdentifier {
            let parts = StringUtils.split(rankedId, "-")
            assert(
                parts.length == 3,
                message: "Invalid rankedId format, should be <type>-<rank>-<id>"
            )
            let type = FRC20Storefront.ListingType(rawValue: UInt8.fromString(parts[0]) ?? panic("Invalid type"))
                ?? panic("Invalid listing type")
            let rank = UInt64.fromString(parts[1]) ?? panic("Invalid rank")
            let id = UInt64.fromString(parts[2]) ?? panic("Invalid id")
            return ItemIdentifier(type: type, rank: rank, listingId: id)
        }

        /// Borrow or create the collection
        ///
        access(self)
        fun borrowOrCreateCollection(
            _ type: FRC20Storefront.ListingType,
            _ rank: UInt64
        ): &ListingCollection {
            var tryDictRef = self._borrowCollectionDict(type)
            if tryDictRef == nil {
                self.collections[type] <-! {}
                tryDictRef = self._borrowCollectionDict(type)
            }
            let dictRef = tryDictRef!
            var collRef = &dictRef[rank] as &ListingCollection?
            if collRef == nil {
                dictRef[rank] <-! create ListingCollection()
                collRef = &dictRef[rank] as &ListingCollection?
            }
            return collRef ?? panic("Failed to create collection")
        }

        /// Get the collection by rank
        access(self)
        fun borrowCollection(
            _ type: FRC20Storefront.ListingType,
            _ rank: UInt64
        ): &ListingCollection? {
            if let colDictRef = self._borrowCollectionDict(type) {
                return &colDictRef[rank] as &ListingCollection?
            }
            return nil
        }

        access(self)
        fun _borrowCollectionDict(
            _ type: FRC20Storefront.ListingType
        ): &{UInt64: ListingCollection}? {
            return &self.collections[type] as &{UInt64: ListingCollection}?
        }

    }

    /** ---– Account Access methods ---- */

    // NOTHING

    /** ---– Public methods ---- */

    /// The helper method to get the market resource reference
    ///
    access(all)
    fun borrowMarket(_ addr: Address): &Market{MarketPublic}? {
        return getAccount(addr)
            .getCapability<&Market{MarketPublic}>(self.FRC20MarketPublicPath)
            .borrow()
    }

    /// Create a new market
    ///
    access(all)
    fun createMarket(_ tick: String): @Market {
        let market <- create Market(tick: tick)
        emit MarketCreated(tick: tick, uuid: market.uuid)
        return <- market
    }

    init() {
        let identifier = "FRC20Market_".concat(self.account.address.toString())
        self.FRC20MarketStoragePath = StoragePath(identifier: identifier)!
        self.FRC20MarketPublicPath = PublicPath(identifier: identifier)!

        emit ContractInitialized()
    }
}
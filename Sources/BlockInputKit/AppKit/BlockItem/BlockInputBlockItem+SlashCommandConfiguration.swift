extension BlockInputBlockItem {
    func applySlashCommandConfiguration(
        rawSlashCommandChips: Bool,
        selectAllBehavior: BlockInputSelectAllBehavior,
        slashCommandAvailability: BlockInputSlashCommandAvailability,
        isDocumentStartBlock: Bool
    ) {
        self.rawSlashCommandChips = rawSlashCommandChips
        self.selectAllBehavior = selectAllBehavior
        self.slashCommandAvailability = slashCommandAvailability
        self.isDocumentStartBlock = isDocumentStartBlock
    }
}

module LibraryEditReceipts
  private

  def expose_library_edit(changes)
    receipt = LibraryChanges::PageReceipt.issue(changes:, user: current_user,
      page_session: request.headers[LibraryChanges::PageReceipt::SESSION_HEADER])
    return unless receipt

    response.set_header(LibraryChanges::PageReceipt::HEADER, receipt)
    response.set_header(LibraryChanges::PageReceipt::SESSION_HEADER,
      request.headers[LibraryChanges::PageReceipt::SESSION_HEADER])
  end
end

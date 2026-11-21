//
//  ErrorLogViewController.swift
//  AltStore
//
//  Created by Riley Testut on 9/6/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
import CoreData
import Nuke
import SwiftUI

final class ErrorLogViewController: UITableViewController
{
    private lazy var dataSource = self.makeDataSource()
    private var expandedErrorIDs = Set<NSManagedObjectID>()
    
    private var isScrolling = false {
        didSet {
            guard self.isScrolling != oldValue else { return }
            self.updateButtonInteractivity()
        }
    }

    private lazy var timeFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .short
        return dateFormatter
    }()
    
    @IBOutlet private var exportLogButton: UIBarButtonItem?
    @IBOutlet private var clearLogButton: UIBarButtonItem!
    
    private var _exportedLogURL: URL?
    
    #if !os(tvOS)
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    #endif
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.tableView.dataSource = self.dataSource
        self.dataSource.contentView = self.tableView
        self.tableView.prefetchDataSource = self.dataSource

        #if os(iOS)
        // Shell styling (the storyboard leaves the table system-default).
        self.tableView.backgroundColor = ShellTheme.background
        self.tableView.separatorColor = ShellTheme.separator
        self.tableView.sectionHeaderTopPadding = 0
        // The export spinner was white for the old dark nav bar; the shell
        // bar is light in light mode, where white is invisible.
        self.exportLogButton?.activityIndicatorView.color = ShellTheme.accentColor
        #else
        self.exportLogButton?.activityIndicatorView.color = .white
        #endif
        
        if #unavailable(iOS 15)
        {
            // Assign just clearLogButton to hide export button.
            self.navigationItem.rightBarButtonItems = [self.clearLogButton]
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        guard let loggedError = sender as? LoggedError, segue.identifier == "showErrorDetails" else { return }
        
        let navigationController = segue.destination as! UINavigationController
        
        let errorDetailsViewController = navigationController.viewControllers.first as! ErrorDetailsViewController
        errorDetailsViewController.loggedError = loggedError
    }
    
    @IBAction private func unwindFromErrorDetails(_ segue: UIStoryboardSegue)
    {
    }
}

private extension ErrorLogViewController
{
    func makeDataSource() -> FetchedResultsTableViewPrefetchingDataSource<LoggedError, UIImage>
    {
        let fetchRequest = LoggedError.fetchRequest() as NSFetchRequest<LoggedError>
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \LoggedError.date, ascending: false)]
        fetchRequest.returnsObjectsAsFaults = false
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext, sectionNameKeyPath: #keyPath(LoggedError.localizedDateString), cacheName: nil)
        
        let dataSource = FetchedResultsTableViewPrefetchingDataSource<LoggedError, UIImage>(fetchedResultsController: fetchedResultsController)
        dataSource.proxy = self
        dataSource.rowAnimation = .fade
        dataSource.cellConfigurationHandler = { [weak self] (cell, loggedError, indexPath) in
            guard let self else { return }
            
            let cell = cell as! ErrorLogTableViewCell
            cell.dateLabel.text = self.timeFormatter.string(from: loggedError.date)
            cell.errorFailureLabel.text = loggedError.localizedFailure ?? NSLocalizedString("Operation Failed", comment: "")
            cell.errorCodeLabel.text = loggedError.error.localizedErrorCode

            #if os(iOS)
            // Shell styling (the storyboard leaves the cells system-default,
            // including fixed 0.66-white secondary labels that wash out in
            // light mode).
            cell.backgroundColor = ShellTheme.card
            cell.dateLabel.textColor = ShellTheme.secondaryText
            cell.errorFailureLabel.textColor = ShellTheme.primaryText
            cell.errorCodeLabel.textColor = ShellTheme.secondaryText
            cell.errorDescriptionTextView.textColor = ShellTheme.secondaryText
            #endif
            
            let nsError = loggedError.error as NSError
            let errorDescription = [nsError.localizedDescription, nsError.localizedRecoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")
            cell.errorDescriptionTextView.text = errorDescription
            cell.errorDescriptionTextView.maximumNumberOfLines = 5
            cell.errorDescriptionTextView.isCollapsed = !self.expandedErrorIDs.contains(loggedError.objectID)
            cell.errorDescriptionTextView.moreButton.addTarget(self, action: #selector(ErrorLogViewController.toggleCollapsingCell(_:)), for: .primaryActionTriggered)
            
            cell.appIconImageView.image = nil
            cell.appIconImageView.isIndicatingActivity = true
            cell.appIconImageView.layer.borderColor = UIColor.gray.cgColor
            
            let displayScale = (self.traitCollection.displayScale == 0.0) ? 1.0 : self.traitCollection.displayScale // 0.0 == "unspecified"
            cell.appIconImageView.layer.borderWidth = 1.0 / displayScale
                        
            cell.menuButton.isHidden = true
            if #available(tvOS 17.0, *) {
                cell.menuButton.menu = nil
            }
            cell.selectionStyle = .none

            // Include errorDescriptionTextView's text in cell summary.
            cell.accessibilityLabel = [cell.errorFailureLabel.text, cell.dateLabel.text, cell.errorCodeLabel.text, cell.errorDescriptionTextView.text].compactMap { $0 }.joined(separator: ". ")
            
            // Group all paragraphs together into single accessibility element (otherwise, each paragraph is independently selectable).
            cell.errorDescriptionTextView.accessibilityLabel = cell.errorDescriptionTextView.text
        }
        dataSource.prefetchHandler = { (loggedError, indexPath) in
            let (installedApp, iconURL) = await loggedError.managedObjectContext?.perform {
                (loggedError.installedApp, loggedError.storeApp?.iconURL)
            } ?? (nil, nil)
            
            if let installedApp {
                return try await installedApp.loadIcon()
            } else if let iconURL {
                return try await ImagePipeline.shared.image(for: iconURL)
            } else {
                return nil
            }
        }
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! ErrorLogTableViewCell
            cell.appIconImageView.image = image
            cell.appIconImageView.isIndicatingActivity = false
        }
        
        let placeholderView = PlaceholderView()
        placeholderView.textLabel.text = NSLocalizedString("No Errors", comment: "")
        placeholderView.detailTextLabel.text = NSLocalizedString("Errors that occur when sideloading or refreshing apps will appear here.", comment: "")
        #if os(iOS)
        placeholderView.textLabel.textColor = ShellTheme.primaryText
        placeholderView.detailTextLabel.textColor = ShellTheme.secondaryText
        #endif
        dataSource.placeholderView = placeholderView
        
        return dataSource
    }
}

private extension ErrorLogViewController
{
    @IBAction func toggleCollapsingCell(_ sender: UIButton)
    {
        let point = self.tableView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.tableView.indexPathForRow(at: point), let cell = self.tableView.cellForRow(at: indexPath) as? ErrorLogTableViewCell else { return }
        
        let loggedError = self.dataSource.item(at: indexPath)
        
        if cell.errorDescriptionTextView.isCollapsed
        {
            self.expandedErrorIDs.remove(loggedError.objectID)
        }
        else
        {
            self.expandedErrorIDs.insert(loggedError.objectID)
        }
        
        self.tableView.performBatchUpdates {
            cell.layoutIfNeeded()
        }
    }
    
    
    enum LogView: String {
        case consoleLog = "console-log"

        func getLogPath() -> URL {
            let appDelegate = UIApplication.shared.delegate as! AppDelegate
            return appDelegate.consoleLog.logFileURL
        }
    }
    
    @IBAction func showConsoleLogs(_ sender: UIBarButtonItem) {
        // Create the SwiftUI ConsoleLogView with the URL
        let consoleLogView = ConsoleLogView(logURL: (UIApplication.shared.delegate as! AppDelegate).consoleLog.logFileURL)

        // Create the UIHostingController
        #if os(iOS)
        let consoleLogController = ShellHostingController(rootView: consoleLogView)
        #else
        let consoleLogController = UIHostingController(rootView: consoleLogView)
        #endif
        
        // Configure the bottom sheet presentation
        #if !os(tvOS)
        consoleLogController.modalPresentationStyle = .pageSheet
        if let sheet = consoleLogController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]  // You can adjust the size of the sheet (medium/large)
            sheet.prefersGrabberVisible = true    // Optional: Shows a grabber at the top of the sheet
            sheet.selectedDetentIdentifier = .large  // Default size when presented
        }
        #endif
        
        // Present the bottom sheet
        present(consoleLogController, animated: true, completion: nil)
    }
        
    @IBAction func clearLoggedErrors(_ sender: UIBarButtonItem)
    {
        let alertController = UIAlertController(title: NSLocalizedString("Are you sure you want to clear the error log?", comment: ""), message: nil, preferredStyle: .actionSheet)
        alertController.popoverPresentationController?.barButtonItem = sender
        alertController.addAction(.cancel)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Clear Error Log", comment: ""), style: .destructive) { _ in
            Task {
                await self.clearLoggedErrors()
            }
        })
        self.present(alertController, animated: true)
    }
    
    func clearLoggedErrors() async
    {
        do
        {
            try await DatabaseManager.shared.purgeLoggedErrors()
        }
        catch
        {
            let alertController = UIAlertController(
                title: NSLocalizedString("Failed to Clear Error Log", comment: ""),
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alertController.addAction(.ok)
            self.present(alertController, animated: true)
        }
    }
    
    func copyErrorMessage(for loggedError: LoggedError)
    {
        #if !os(tvOS)
        let nsError = loggedError.error as NSError
        let errorMessage = [nsError.localizedDescription, nsError.localizedRecoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")
        
        UIPasteboard.general.string = errorMessage
        #endif
    }
    
    func copyErrorCode(for loggedError: LoggedError)
    {
        #if !os(tvOS)
        let errorCode = loggedError.error.localizedErrorCode
        UIPasteboard.general.string = errorCode
        #endif
    }
    
    func searchFAQ(for loggedError: LoggedError)
    {
        let staticURL = AppConstants.URLs.errorCodesDocumentation
        #if os(iOS)
        self.openWebURL(staticURL, preferredTintColor: ShellTheme.accentColor)
        #else
        self.openWebURL(staticURL, preferredTintColor: .altPrimary)
        #endif
    }

    func viewMoreDetails(for loggedError: LoggedError) {
        self.performSegue(withIdentifier: "showErrorDetails", sender: loggedError)
    }
}

extension ErrorLogViewController
{
    @available(tvOS 17.0, *)
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration?
    {
        let loggedError = self.dataSource.item(at: indexPath)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            return UIMenu(title: "", children: [
                UIAction(title: NSLocalizedString("Copy Error Message", comment: ""), image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                    self?.copyErrorMessage(for: loggedError)
                },
                UIAction(title: NSLocalizedString("Copy Error Code", comment: ""), image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                    self?.copyErrorCode(for: loggedError)
                },
                UIAction(title: NSLocalizedString("Search FAQ", comment: ""), image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in
                    self?.searchFAQ(for: loggedError)
                },
                UIAction(title: NSLocalizedString("View More Details", comment: ""), image: UIImage(systemName: "ellipsis.circle")) { [weak self] _ in
                    self?.viewMoreDetails(for: loggedError)
                },
            ])
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let cell = tableView.cellForRow(at: indexPath) as? ErrorLogTableViewCell else { return }
        
        if !cell.errorDescriptionTextView.moreButton.isHidden
        {
            self.toggleCollapsingCell(cell.errorDescriptionTextView.moreButton)
        }
    }
    
    #if !os(tvOS)
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration?
    {
        let deleteAction = UIContextualAction(style: .destructive, title: NSLocalizedString("Delete", comment: "")) { _, _, completion in
            let loggedError = self.dataSource.item(at: indexPath)
            DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
                do
                {
                    let loggedError = context.object(with: loggedError.objectID) as! LoggedError
                    context.delete(loggedError)
                    
                    try context.save()
                    DispatchQueue.main.async {
                        completion(true)
                    }
                }
                catch
                {
                    debugLog("[oPenSSAI] Failed to delete LoggedError \(loggedError.objectID): \(error)")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                }
            }
        }
        
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
    #endif
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
    {
        return self.headerTitle(forSection: section)
    }

    #if os(iOS)
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView?
    {
        guard let title = self.headerTitle(forSection: section) else { return nil }

        let container = UIView()
        let label = UILabel()
        label.font = ShellTheme.sectionTitleFont
        label.textColor = ShellTheme.secondaryText
        label.text = title
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
        ])

        return container
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat
    {
        return 40
    }
    #endif

    private func headerTitle(forSection section: Int) -> String?
    {
        let indexPath = IndexPath(row: 0, section: section)
        let loggedError = self.dataSource.item(at: indexPath)

        if Calendar.current.isDateInToday(loggedError.date)
        {
            return NSLocalizedString("Today", comment: "")
        }
        else
        {
            return loggedError.localizedDateString
        }
    }
}



extension ErrorLogViewController
{
    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView)
    {
        self.isScrolling = true
    }
    override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView)
    {
        self.isScrolling = false
    }
    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool)
    {
        guard !decelerate else { return }
        self.isScrolling = false
    }
    private func updateButtonInteractivity()
    {
        if #available(tvOS 17.0, *) {
            for case let cell as ErrorLogTableViewCell in self.tableView.visibleCells
            {
                if self.isScrolling
                {
                    cell.menuButton.showsMenuAsPrimaryAction = false
                }
                else
                {
                    cell.menuButton.showsMenuAsPrimaryAction = true
                }
            }
        }
    }
}

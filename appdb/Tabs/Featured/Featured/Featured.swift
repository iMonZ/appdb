//
//  Featured.swift
//  appdb
//
//  Created by ned on 11/10/2016.
//  Copyright © 2016 ned. All rights reserved.
//

import UIKit
import Cartography
import Localize_Swift

protocol ChangeCategory: class {
    func openCategories(_ sender: AnyObject)
    func reloadViewAfterCategoryChange(id: String, type: ItemType)
}

protocol ContentRedirection: class {
    func pushDetailsController(with content: Item)
    func pushSeeAllController(title: String, type: ItemType, category: String, price: Price, order: Order)
}

class Featured: LoadingTableView, UIPopoverPresentationControllerDelegate {

    let cells: [FeaturedCell] = [
        ItemCollection(id: .cydia, title: "Custom Apps".localized(), fullSeparator: true),
        Dummy(),
        ItemCollection(id: .iosNew, title: "New and Noteworthy".localized()),
        ItemCollection(id: .iosPaid, title: "Top Paid".localized()),
        ItemCollection(id: .iosPopular, title: "Popular This Week".localized(), fullSeparator: true),
        Dummy(),
        ItemCollection(id: .books, title: "Top Books".localized(), fullSeparator: true),
        Copyright()
    ]

    var banner = Banner()

    override func viewDidLoad() {
        super.viewDidLoad()

        // Set up
        title = "Featured".localized()
        setUp()
        state = .loading
        animated = true

        // Add categories button
        let categoriesButton = UIBarButtonItem(title: "Categories".localized(), style: .plain, target: self, action: #selector(self.openCategories))
        navigationItem.leftBarButtonItem = categoriesButton
        navigationItem.leftBarButtonItem?.isEnabled = false

        // Add wishes button

        let wishesButton = UIBarButtonItem(image: UIImage(named: "wishes"), style: .plain, target: self, action: #selector(self.openWishes))
        navigationItem.rightBarButtonItem = wishesButton
        navigationItem.rightBarButtonItem?.isEnabled = false

        // Fix random separator margin issues
        if #available(iOS 9, *) { tableView.cellLayoutMarginsFollowReadableWidth = false }

        // List Genres and enable button on completion
        API.listGenres(completion: { [weak self] in
            guard let self = self else { return }

            // Enable categories button
            self.navigationItem.leftBarButtonItem?.isEnabled = true

            // Enable wishes button
            self.navigationItem.rightBarButtonItem?.isEnabled = true
        })

        // Wait for data to be fetched, reload tableView on completion
        reloadTableWhenReady()

        // Preload view controllers
        for viewController in tabBarController?.viewControllers ?? [] {
            if let navigationVC = viewController as? UINavigationController, let rootVC = navigationVC.viewControllers.first {
                _ = rootVC.view
            }
        }
    }

    // MARK: - Load Initial Data

    func reloadTableWhenReady() {
        let itemCells = cells.compactMap {$0 as? ItemCollection}
        if itemCells.count != (itemCells.filter {$0.response.success == true}.count) {
            if let first = itemCells.first(where: {!$0.response.errorDescription.isEmpty}) {
                let error = first.response.errorDescription
                showErrorMessage(text: "Cannot connect".localized(), secondaryText: error)

                // Button target action to retry loading
                refreshButton.addTarget(self, action: #selector(self.retry), for: .touchUpInside)
            } else {
                // Not ready, retrying in 0.3 seconds
                delay(0.3) { self.reloadTableWhenReady() }
            }
        } else {
            // If i don't do this here, stuff breaks :(
            for layout in itemCells.compactMap({$0.collectionView.collectionViewLayout as? SnappableFlowLayout}) { layout.scrollDirection = .horizontal }

            // Add banner
            addBanner(self.banner)

            // Works around crazy cell bugs on rotation, enables preloading
            tableView.estimatedRowHeight = 32
            tableView.rowHeight = UITableView.automaticDimension

            // Reload tableView (animated), hide spinner
            state = .done

            // Check if there is a new update available
            API.checkIfUpdateIsAvailable(success: { [weak self] (update: CydiaApp, linkId: String) in
                guard let self = self else { return }

                let appUpdateController = AppUpdateController(updatedApp: update, linkId: linkId)
                let nav = AppUpdateNavController(rootViewController: appUpdateController)
                appUpdateController.delegate = nav
                let segue = Messages.shared.generateModalSegue(vc: nav, source: self)
                segue.perform()
            })
        }
    }

    // MARK: - Retry Loading

    @objc func retry() {
        state = .loading

        delay(0.3) {
            // Retry all network operations
            API.listGenres(completion: { [weak self] in
                guard let self = self else { return }

                // Enable categories button
                self.navigationItem.leftBarButtonItem?.isEnabled = true

                // Enable wishes button
                self.navigationItem.rightBarButtonItem?.isEnabled = true
            })

            for cell in self.cells.compactMap({$0 as? ItemCollection}) { cell.requestItems() }
            //self.banner.setImageInputs()
            self.reloadTableWhenReady()
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return state == .done ? cells.count : 0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return state == .done ? cells[indexPath.row] : UITableViewCell()
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return state == .done ? cells[indexPath.row].height : 0
    }

    // Open wishes
    @objc func openWishes(_ sender: AnyObject) {
        let wishesController = Wishes()
        if Global.isIpad {
            let nav = DismissableModalNavController(rootViewController: wishesController)
            nav.modalPresentationStyle = .formSheet
            self.navigationController?.present(nav, animated: true)
        } else {
            self.navigationController?.present(UINavigationController(rootViewController: wishesController), animated: true)
        }
    }
}

////////////////////////////////
//  PROTOCOL IMPLEMENTATIONS  //
////////////////////////////////

// MARK: - Reload view after category change
extension Featured: ChangeCategory {

    // Open categories
    @objc func openCategories(_ sender: AnyObject) {
        let categoriesViewController = Categories()
        categoriesViewController.delegate = self
        let nav = UINavigationController(rootViewController: categoriesViewController)
        nav.modalPresentationStyle = .popover
        nav.preferredContentSize = CGSize(width: 350, height: 500)
        if let popover = nav.popoverPresentationController {
            popover.delegate = self
            popover.theme_backgroundColor = Color.popoverArrowColor
            if let view = sender.value(forKey: "view") as? UIView {
                popover.sourceView = view
                popover.sourceRect = view.bounds
            }
        }
        present(nav, animated: true, completion: nil)
    }

    // Popover on ipad, modal on iphone
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle { return .fullScreen }

    // Reload Categories
    func reloadViewAfterCategoryChange(id: String, type: ItemType) {
        for cell in cells { if let collection = cell as? ItemCollection {
            collection.reloadAfterCategoryChange(id: id, type: type)
        } }
    }
}

// MARK: - Push Details controller
extension Featured: ContentRedirection {
    func pushDetailsController(with content: Item) {
        let detailsViewController = Details(content: content)
        if Global.isIpad {
            let nav = DismissableModalNavController(rootViewController: detailsViewController)
            nav.modalPresentationStyle = .formSheet
            navigationController?.present(nav, animated: true)
        } else {
            navigationController?.pushViewController(detailsViewController, animated: true)
        }
    }

    func pushSeeAllController(title: String, type: ItemType, category: String, price: Price, order: Order) {
        let seeAllViewController = SeeAll(title: title, type: type, category: category, price: price, order: order)
        if Global.isIpad {
            let nav = DismissableModalNavController(rootViewController: seeAllViewController)
            nav.modalPresentationStyle = .formSheet
            navigationController?.present(nav, animated: true)
        } else {
            navigationController?.pushViewController(seeAllViewController, animated: true)
        }
    }
}

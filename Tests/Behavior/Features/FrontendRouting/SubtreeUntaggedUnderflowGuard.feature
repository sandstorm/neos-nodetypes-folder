@flowEntities @contentrepository
Feature: Soft-removing and reinstating subtrees stays consistent across transparent folders

  Editors can soft-remove a subtree (tag it as "removed") to take it offline
  and later reinstate it. Two requirements must hold even when a transparent
  folder sits in the chain:
    - while removed, the descendant URL must stop matching.
    - after reinstating, the descendant URL must match again at its
      original (transparent) location.

  In addition: if both a parent and its child are tagged as removed and only
  the parent is untagged, the child stays removed — and the projection must
  not get into an inconsistent state. A subsequent untag of the child then
  reinstates it normally.

      lady-eleonode-rootford
      └─ site-of-folders        (Test.Routing.Page, name "node1", segment "site-ignored")
         └─ folder-a             (Folder, hide=true, segment "folder-a")
            └─ child-in-folder   (Test.Routing.Page, segment "child")

  Background:
    Given using no content dimensions
    And using the following node types:
    """yaml
    'Neos.Neos:Sites':
      superTypes:
        'Neos.ContentRepository:Root': true
    'Neos.Neos:Document': {}
    'Neos.Neos:Content': {}
    'Neos.Neos:Test.Routing.Page':
      superTypes:
        'Neos.Neos:Document': true
      properties:
        uriPathSegment:
          type: string
    'Sandstorm.NodeTypes.Folder:Mixin.HideUriSegment':
      abstract: true
      properties:
        hideSegmentInUriPath:
          type: boolean
          defaultValue: true
    'Sandstorm.NodeTypes.Folder:Document.Folder':
      superTypes:
        'Neos.Neos:Document': true
        'Sandstorm.NodeTypes.Folder:Mixin.HideUriSegment': true
      properties:
        uriPathSegment:
          type: string
    """
    And using identifier "default", I define a content repository
    And I am in content repository "default"
    And I am user identified by "initiating-user-identifier"
    When the command CreateRootWorkspace is executed with payload:
      | Key                | Value           |
      | workspaceName      | "live"          |
      | newContentStreamId | "cs-identifier" |
    And I am in workspace "live" and dimension space point {}
    And the command CreateRootNodeAggregateWithNode is executed with payload:
      | Key             | Value                    |
      | nodeAggregateId | "lady-eleonode-rootford" |
      | nodeTypeName    | "Neos.Neos:Sites"        |
    And the following CreateNodeAggregateWithNode commands are executed:
      | nodeAggregateId | parentNodeAggregateId  | nodeTypeName                                  | initialPropertyValues                                          | nodeName |
      | site-of-folders | lady-eleonode-rootford | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "site-ignored"}                             | node1    |
      | folder-a        | site-of-folders        | Sandstorm.NodeTypes.Folder:Document.Folder    | {"uriPathSegment": "folder-a", "hideSegmentInUriPath": true}   | folderA  |
      | child-in-folder | folder-a               | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "child"}                                    | child    |
    And A site exists for node name "node1"
    And the sites configuration is:
    """yaml
    Neos:
      Neos:
        sites:
          'node1':
            preset: 'default'
            uriPathSuffix: ''
            contentDimensions:
              resolver:
                factoryClassName: Neos\Neos\FrontendRouting\DimensionResolution\Resolver\NoopResolverFactory
    """

  Scenario: Soft-removing the transparent folder hides descendants
    When the command TagSubtree is executed with payload:
      | Key                          | Value         |
      | nodeAggregateId              | "folder-a"    |
      | coveredDimensionSpacePoint   | {}            |
      | nodeVariantSelectionStrategy | "allVariants" |
      | tag                          | "removed"     |
    Then No node should match URL "/child"
    And The node "child-in-folder" in dimension "{}" should not resolve to an URL

  Scenario: Soft-removing then reinstating the transparent folder restores descendants
    When the command TagSubtree is executed with payload:
      | Key                          | Value         |
      | nodeAggregateId              | "folder-a"    |
      | coveredDimensionSpacePoint   | {}            |
      | nodeVariantSelectionStrategy | "allVariants" |
      | tag                          | "removed"     |
    And the command UntagSubtree is executed with payload:
      | Key                          | Value         |
      | nodeAggregateId              | "folder-a"    |
      | coveredDimensionSpacePoint   | {}            |
      | nodeVariantSelectionStrategy | "allVariants" |
      | tag                          | "removed"     |
    And I am on URL "/child"
    Then the matched node should be "child-in-folder" in dimension "{}"
    And The node "child-in-folder" in dimension "{}" should resolve to URL "/child"

  Scenario: Untagging only the parent leaves an independently-tagged child removed
    # Both folder-a and child-in-folder are tagged as removed.
    # Untagging only folder-a must NOT reinstate the child (the child was tagged
    # explicitly, not just by inheritance). A second untag of the child then
    # reinstates it and its URL matches again.
    When the command TagSubtree is executed with payload:
      | Key                          | Value         |
      | nodeAggregateId              | "folder-a"    |
      | coveredDimensionSpacePoint   | {}            |
      | nodeVariantSelectionStrategy | "allVariants" |
      | tag                          | "removed"     |
    And the command TagSubtree is executed with payload:
      | Key                          | Value             |
      | nodeAggregateId              | "child-in-folder" |
      | coveredDimensionSpacePoint   | {}                |
      | nodeVariantSelectionStrategy | "allVariants"     |
      | tag                          | "removed"         |
    And the command UntagSubtree is executed with payload:
      | Key                          | Value         |
      | nodeAggregateId              | "folder-a"    |
      | coveredDimensionSpacePoint   | {}            |
      | nodeVariantSelectionStrategy | "allVariants" |
      | tag                          | "removed"     |
    Then No node should match URL "/child"
    And The node "child-in-folder" in dimension "{}" should not resolve to an URL
    When the command UntagSubtree is executed with payload:
      | Key                          | Value             |
      | nodeAggregateId              | "child-in-folder" |
      | coveredDimensionSpacePoint   | {}                |
      | nodeVariantSelectionStrategy | "allVariants"     |
      | tag                          | "removed"         |
    And I am on URL "/child"
    Then the matched node should be "child-in-folder" in dimension "{}"

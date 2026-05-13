@flowEntities @contentrepository
Feature: Disabling a folder hides its descendants from URL routing; re-enabling brings them back

  Apart from soft-removal (TagSubtree), editors can also disable a subtree
  via DisableNodeAggregate to take it temporarily offline. The same routing
  invariants must hold even when a transparent folder is in the chain:
    - while disabled, the descendant URL must stop matching.
    - re-enabling brings the URL back at its original (transparent) location.

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

  Scenario: Disabling the transparent folder removes the descendant from URL matching
    When the command DisableNodeAggregate is executed with payload:
      | Key                          | Value         |
      | nodeAggregateId              | "folder-a"    |
      | coveredDimensionSpacePoint   | {}            |
      | nodeVariantSelectionStrategy | "allVariants" |
    Then No node should match URL "/child"
    # contraire to matching, we DO allow resolving of disabled nodes https://github.com/neos/neos-development-collection/pull/4363
    And The node "child-in-folder" in dimension "{}" should resolve to URL "/child"

  Scenario: Re-enabling the folder brings the descendant URL back
    When the command DisableNodeAggregate is executed with payload:
      | Key                          | Value         |
      | nodeAggregateId              | "folder-a"    |
      | coveredDimensionSpacePoint   | {}            |
      | nodeVariantSelectionStrategy | "allVariants" |
    And the command EnableNodeAggregate is executed with payload:
      | Key                          | Value         |
      | nodeAggregateId              | "folder-a"    |
      | coveredDimensionSpacePoint   | {}            |
      | nodeVariantSelectionStrategy | "allVariants" |
    And I am on URL "/child"
    Then the matched node should be "child-in-folder" in dimension "{}"
    And The node "child-in-folder" in dimension "{}" should resolve to URL "/child"

@flowEntities @contentrepository
Feature: Moving a node into a parent where its URL would collide is rejected

  Drag-and-drop reparenting in the editor recomputes the moved node's URL
  against the new parent. If the new parent is a transparent folder, the
  moved node's URL ends up in the same space as the folder's siblings —
  which may already host a node with that exact segment. We reject the move
  before it corrupts routing.

  Moving with no collision continues to work normally.

      lady-eleonode-rootford
      └─ site-of-folders        (Test.Routing.Page, name "node1", segment "site-ignored")
         ├─ folder-a             (Folder, hide=true, segment "folder-a")
         │  └─ child-in-folder   (Test.Routing.Page, segment "child")
         ├─ folder-b             (Folder, hide=false, segment "folder-b")  ← opaque, so mover lives at /folder-b/sibling here
         │  └─ mover             (Test.Routing.Page, segment "sibling")    ← would collide if moved under folder-a (transparent)
         └─ sibling-of-folder    (Test.Routing.Page, segment "sibling")

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
      | nodeAggregateId   | parentNodeAggregateId  | nodeTypeName                                  | initialPropertyValues                                          | nodeName |
      | site-of-folders   | lady-eleonode-rootford | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "site-ignored"}                             | node1    |
      | folder-a          | site-of-folders        | Sandstorm.NodeTypes.Folder:Document.Folder    | {"uriPathSegment": "folder-a", "hideSegmentInUriPath": true}   | folderA  |
      | child-in-folder   | folder-a               | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "child"}                                    | child    |
      | folder-b          | site-of-folders        | Sandstorm.NodeTypes.Folder:Document.Folder    | {"uriPathSegment": "folder-b", "hideSegmentInUriPath": false}  | folderB  |
      | mover             | folder-b               | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "sibling"}                                  | mover    |
      | sibling-of-folder | site-of-folders        | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "sibling"}                                  | sibling  |
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

  Scenario: Moving a node into another transparent folder where its segment collides is rejected
    When the command MoveNodeAggregate is executed with payload and exceptions are caught:
      | Key                                 | Value      |
      | nodeAggregateId                     | "mover"    |
      | dimensionSpacePoint                 | {}         |
      | newParentNodeAggregateId            | "folder-a" |
      | newSucceedingSiblingNodeAggregateId | null       |
    Then the last command should have thrown an exception of type "UriPathCollisionDetected"

  Scenario: Moving a node where the collision has first been removed succeeds
    # mover's segment is "sibling"; once we delete sibling-of-folder, the URL "/sibling" is free.
    When the command RemoveNodeAggregate is executed with payload:
      | Key                          | Value               |
      | nodeAggregateId              | "sibling-of-folder" |
      | coveredDimensionSpacePoint   | {}                  |
      | nodeVariantSelectionStrategy | "allVariants"       |
    And the command MoveNodeAggregate is executed with payload:
      | Key                                 | Value      |
      | nodeAggregateId                     | "mover"    |
      | dimensionSpacePoint                 | {}         |
      | newParentNodeAggregateId            | "folder-a" |
      | newSucceedingSiblingNodeAggregateId | null       |
    And I am on URL "/"
    Then the node "mover" in dimension "{}" should resolve to URL "/sibling"
    When I am on URL "/sibling"
    Then the matched node should be "mover" in dimension "{}"

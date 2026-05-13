@flowEntities @contentrepository
Feature: Renaming a node into a colliding URL segment is rejected

  Editors routinely rename a page's URL segment to something more readable.
  When the renamed page sits under a transparent folder, its new segment
  shares URL-space with the folder's own siblings — so a rename to an
  already-taken segment would put two nodes at the same URL. We reject the
  rename rather than silently breaking either one.

  Renaming to a unique segment continues to work. Re-setting the current
  segment (a no-op rename) must not be rejected just because the row
  technically matches itself.

      lady-eleonode-rootford
      └─ site-of-folders        (Test.Routing.Page, name "node1", segment "site-ignored")
         ├─ folder-a             (Folder, hide=true, segment "folder-a")
         │  └─ child-in-folder   (Test.Routing.Page, segment "child")     ← gets renamed
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

  Scenario: Renaming a folder-child to a colliding sibling segment is rejected
    When the command SetNodeProperties is executed with payload and exceptions are caught:
      | Key                       | Value                            |
      | nodeAggregateId           | "child-in-folder"                |
      | originDimensionSpacePoint | {}                               |
      | propertyValues            | {"uriPathSegment": "sibling"}    |
    Then the last command should have thrown an exception of type "UriPathCollisionDetected"

  Scenario: Renaming to a unique segment succeeds and the URL flips
    When the command SetNodeProperties is executed with payload:
      | Key                       | Value                              |
      | nodeAggregateId           | "child-in-folder"                  |
      | originDimensionSpacePoint | {}                                 |
      | propertyValues            | {"uriPathSegment": "new-segment"}  |
    And I am on URL "/"
    Then the node "child-in-folder" in dimension "{}" should resolve to URL "/new-segment"
    When I am on URL "/child"
    Then No node should match URL "/child"

  Scenario: Re-setting the same segment is accepted (no-op rename)
    When the command SetNodeProperties is executed with payload:
      | Key                       | Value                          |
      | nodeAggregateId           | "child-in-folder"              |
      | originDimensionSpacePoint | {}                             |
      | propertyValues            | {"uriPathSegment": "child"}    |
    And I am on URL "/"
    Then the node "child-in-folder" in dimension "{}" should resolve to URL "/child"

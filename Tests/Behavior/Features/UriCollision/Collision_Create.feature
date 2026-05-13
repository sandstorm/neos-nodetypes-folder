@flowEntities @contentrepository
Feature: Creating a node whose URL would collide with an existing node is rejected

  Because a transparent folder hides its own segment, a child created under
  the folder ends up at the same URL space as the folder's own siblings. If
  two nodes would resolve to the same URL the router has to pick one
  arbitrarily — at best users see the wrong page, at worst a shortcut at one
  side ping-pongs to the other in an infinite redirect loop. We catch the
  conflict at write-time and refuse the command.

  When the folder is opaque (hide=false), no collision exists because the
  folder's segment keeps the URL spaces distinct.

      lady-eleonode-rootford
      └─ site-of-folders        (Test.Routing.Page, name "node1", segment "site-ignored")
         ├─ folder-a             (Folder, hide=true, segment "folder-a")
         │  └─ child-in-folder   (Test.Routing.Page, segment "child")
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

  Scenario: Bug E reproduction — adding a child under the transparent folder that collides with a sibling-of-folder is rejected
    When the command CreateNodeAggregateWithNode is executed with payload and exceptions are caught:
      | Key                       | Value                                                                                  |
      | nodeAggregateId           | "new-child"                                                                            |
      | parentNodeAggregateId     | "folder-a"                                                                             |
      | nodeTypeName              | "Neos.Neos:Test.Routing.Page"                                                          |
      | originDimensionSpacePoint | {}                                                                                     |
      | initialPropertyValues     | {"uriPathSegment": "sibling"}                                                          |
    Then the last command should have thrown an exception of type "UriPathCollisionDetected"

  Scenario: Adding a child with a unique segment is accepted
    When the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                         |
      | nodeAggregateId           | "new-child"                   |
      | parentNodeAggregateId     | "folder-a"                    |
      | nodeTypeName              | "Neos.Neos:Test.Routing.Page" |
      | originDimensionSpacePoint | {}                            |
      | initialPropertyValues     | {"uriPathSegment": "unique"}  |
    And I am on URL "/"
    Then the node "new-child" in dimension "{}" should resolve to URL "/unique"

  Scenario: Same create succeeds when the folder is opaque (segment lives in distinct URL space)
    Given the command SetNodeProperties is executed with payload:
      | Key                       | Value                            |
      | nodeAggregateId           | "folder-a"                       |
      | originDimensionSpacePoint | {}                               |
      | propertyValues            | {"hideSegmentInUriPath": false}  |
    When the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                         |
      | nodeAggregateId           | "new-child"                   |
      | parentNodeAggregateId     | "folder-a"                    |
      | nodeTypeName              | "Neos.Neos:Test.Routing.Page" |
      | originDimensionSpacePoint | {}                            |
      | initialPropertyValues     | {"uriPathSegment": "sibling"} |
    And I am on URL "/"
    Then the node "new-child" in dimension "{}" should resolve to URL "/folder-a/sibling"
    And the node "sibling-of-folder" in dimension "{}" should resolve to URL "/sibling"

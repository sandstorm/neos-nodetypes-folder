@flowEntities @contentrepository
Feature: Siblings must not share a uriPathSegment, even before publishing

  The DocumentUriPath projection only reflects live, so the projection-based
  collision check cannot see nodes that exist only in an editor's workspace.
  Sibling uniqueness is therefore also checked against the workspace's
  content graph: two unpublished children of the same parent must not share
  a uriPathSegment.

  Collisions across transparent folders among unpublished nodes are still
  only caught once one side is published (see the "Known limitation" in
  Docs/2026_05_12_EditorUriCollisionValidator.md).

      lady-eleonode-rootford
      └─ site                   (Test.Routing.Page, name "node1", segment "site-ignored")
         └─ news                (Test.Routing.Page, segment "news")
            ├─ y2025            (Folder, hide=true, segment "2025")
            │  └─ m2025-09      (Folder, hide=true, segment "09")
            │     └─ post-hello (Test.Routing.Page, segment "hello")
            └─ y2026            (Folder, hide=true, segment "2026")

  All of the above is live; every scenario works in the unpublished workspace "user-ws".

  Background:
    Given using no content dimensions
    And using the following node types:
    """yaml
    'Neos.Neos:Sites':
      superTypes:
        'Neos.ContentRepository:Root': true
    'Neos.Neos:Document': {}
    'Neos.Neos:Content': {}
    'Neos.Neos:Shortcut':
      superTypes:
        'Neos.Neos:Document': true
      properties:
        targetMode:
          type: string
          defaultValue: 'firstChildNode'
        target:
          type: string
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
        'Neos.Neos:Shortcut': true
        'Sandstorm.NodeTypes.Folder:Mixin.HideUriSegment': true
      properties:
        uriPathSegment:
          type: string
        targetMode:
          defaultValue: 'noTarget'
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
      | nodeAggregateId | parentNodeAggregateId  | nodeTypeName                               | initialPropertyValues              | nodeName |
      | site            | lady-eleonode-rootford | Neos.Neos:Test.Routing.Page                | {"uriPathSegment": "site-ignored"} | node1    |
      | news            | site                   | Neos.Neos:Test.Routing.Page                | {"uriPathSegment": "news"}         | news     |
      | y2025           | news                   | Sandstorm.NodeTypes.Folder:Document.Folder | {"uriPathSegment": "2025"}         | y2025    |
      | m2025-09        | y2025                  | Sandstorm.NodeTypes.Folder:Document.Folder | {"uriPathSegment": "09"}           | m202509  |
      | post-hello      | m2025-09               | Neos.Neos:Test.Routing.Page                | {"uriPathSegment": "hello"}        | hello    |
      | y2026           | news                   | Sandstorm.NodeTypes.Folder:Document.Folder | {"uriPathSegment": "2026"}         | y2026    |
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
    And the command CreateWorkspace is executed with payload:
      | Key                | Value           |
      | workspaceName      | "user-ws"       |
      | baseWorkspaceName  | "live"          |
      | newContentStreamId | "cs-user-first" |
    And I am in workspace "user-ws" and dimension space point {}

  Scenario: A second unpublished folder with the same segment under the same parent is rejected
    Given the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                                        |
      | nodeAggregateId           | "m2026-09"                                   |
      | parentNodeAggregateId     | "y2026"                                      |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder" |
      | originDimensionSpacePoint | {}                                           |
      | initialPropertyValues     | {"uriPathSegment": "09"}                     |
    When the command CreateNodeAggregateWithNode is executed with payload and exceptions are caught:
      | Key                       | Value                                        |
      | nodeAggregateId           | "m2026-09-duplicate"                         |
      | parentNodeAggregateId     | "y2026"                                      |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder" |
      | originDimensionSpacePoint | {}                                           |
      | initialPropertyValues     | {"uriPathSegment": "09"}                     |
    Then the last command should have thrown an exception of type "UriPathCollisionDetected"

  Scenario: Two unpublished pages with the same segment under the same parent are rejected
    Given the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                         |
      | nodeAggregateId           | "page-a"                      |
      | parentNodeAggregateId     | "news"                        |
      | nodeTypeName              | "Neos.Neos:Test.Routing.Page" |
      | originDimensionSpacePoint | {}                            |
      | initialPropertyValues     | {"uriPathSegment": "about"}   |
    When the command CreateNodeAggregateWithNode is executed with payload and exceptions are caught:
      | Key                       | Value                         |
      | nodeAggregateId           | "page-b"                      |
      | parentNodeAggregateId     | "news"                        |
      | nodeTypeName              | "Neos.Neos:Test.Routing.Page" |
      | originDimensionSpacePoint | {}                            |
      | initialPropertyValues     | {"uriPathSegment": "about"}   |
    Then the last command should have thrown an exception of type "UriPathCollisionDetected"

  Scenario: An unpublished month folder may share its segment with a month of another year
    # The step fails on any exception, so passing means accepted.
    When the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                                        |
      | nodeAggregateId           | "m2026-09"                                   |
      | parentNodeAggregateId     | "y2026"                                      |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder" |
      | originDimensionSpacePoint | {}                                           |
      | initialPropertyValues     | {"uriPathSegment": "09"}                     |

  Scenario: Renaming an unpublished folder to an unpublished sibling's segment is rejected
    Given the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                                        |
      | nodeAggregateId           | "m2026-09"                                   |
      | parentNodeAggregateId     | "y2026"                                      |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder" |
      | originDimensionSpacePoint | {}                                           |
      | initialPropertyValues     | {"uriPathSegment": "09"}                     |
    And the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                                        |
      | nodeAggregateId           | "m2026-10"                                   |
      | parentNodeAggregateId     | "y2026"                                      |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder" |
      | originDimensionSpacePoint | {}                                           |
      | initialPropertyValues     | {"uriPathSegment": "10"}                     |
    When the command SetNodeProperties is executed with payload and exceptions are caught:
      | Key                       | Value                    |
      | nodeAggregateId           | "m2026-10"               |
      | originDimensionSpacePoint | {}                       |
      | propertyValues            | {"uriPathSegment": "09"} |
    Then the last command should have thrown an exception of type "UriPathCollisionDetected"

  Scenario: Moving an unpublished folder next to an unpublished same-named sibling is rejected
    Given the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                                        |
      | nodeAggregateId           | "m2026-09"                                   |
      | parentNodeAggregateId     | "y2026"                                      |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder" |
      | originDimensionSpacePoint | {}                                           |
      | initialPropertyValues     | {"uriPathSegment": "09"}                     |
    And the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                                                       |
      | nodeAggregateId           | "drafts"                                                    |
      | parentNodeAggregateId     | "news"                                                      |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder"                |
      | originDimensionSpacePoint | {}                                                          |
      | initialPropertyValues     | {"uriPathSegment": "drafts", "hideSegmentInUriPath": false} |
    And the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                                        |
      | nodeAggregateId           | "draft-09"                                   |
      | parentNodeAggregateId     | "drafts"                                     |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder" |
      | originDimensionSpacePoint | {}                                           |
      | initialPropertyValues     | {"uriPathSegment": "09"}                     |
    When the command MoveNodeAggregate is executed with payload and exceptions are caught:
      | Key                                 | Value      |
      | nodeAggregateId                     | "draft-09" |
      | dimensionSpacePoint                 | {}         |
      | newParentNodeAggregateId            | "y2026"    |
      | newSucceedingSiblingNodeAggregateId | null       |
    Then the last command should have thrown an exception of type "UriPathCollisionDetected"

  Scenario: The Inspector's collision endpoint reports an unpublished sibling
    # Pages under "news": nothing in live shares the path, so only the
    # workspace sibling check can find the conflict.
    Given the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                         |
      | nodeAggregateId           | "page-a"                      |
      | parentNodeAggregateId     | "news"                        |
      | nodeTypeName              | "Neos.Neos:Test.Routing.Page" |
      | originDimensionSpacePoint | {}                            |
      | initialPropertyValues     | {"uriPathSegment": "about"}   |
    And the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                         |
      | nodeAggregateId           | "page-b"                      |
      | parentNodeAggregateId     | "news"                        |
      | nodeTypeName              | "Neos.Neos:Test.Routing.Page" |
      | originDimensionSpacePoint | {}                            |
      | initialPropertyValues     | {"uriPathSegment": "contact"} |
    When I POST JSON to URL "http://localhost/neos/folder/check-uri-collision":
    """
    {
      "workspaceName": "user-ws",
      "nodeAggregateId": "page-b",
      "parentNodeAggregateId": "news",
      "dimensions": {},
      "propertyValues": {
        "uriPathSegment": "about"
      }
    }
    """
    Then the response status code should be 409
    And the first conflict in the response JSON should contain key "otherNodeAggregateId"

  Scenario: The endpoint accepts renaming an unpublished month folder to another year's month segment
    # The unpublished folder has no projection row; its routability must come
    # from the workspace, or it is treated as routable and "collides" with m2025-09.
    Given the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                                        |
      | nodeAggregateId           | "m2026-10"                                   |
      | parentNodeAggregateId     | "y2026"                                      |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder" |
      | originDimensionSpacePoint | {}                                           |
      | initialPropertyValues     | {"uriPathSegment": "10"}                     |
    When I POST JSON to URL "http://localhost/neos/folder/check-uri-collision":
    """
    {
      "workspaceName": "user-ws",
      "nodeAggregateId": "m2026-10",
      "parentNodeAggregateId": "y2026",
      "dimensions": {},
      "propertyValues": {
        "uriPathSegment": "09"
      }
    }
    """
    Then the response status code should be 200

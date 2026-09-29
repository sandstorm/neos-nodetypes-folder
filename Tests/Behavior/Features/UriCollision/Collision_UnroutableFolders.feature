@flowEntities @contentrepository
Feature: Hidden noTarget folders sharing a uriPath do not collide

  A transparent folder's own row still stores `parent/segment` as uriPath,
  so two hidden month folders "09" under two hidden year folders both
  occupy `/news/09`. That URL is unreachable anyway: a `noTarget` folder
  answers with 404. Such pairs are therefore no collision — typical for
  news archives organised as year/month folders.

  Everything reachable still collides: a page vs. a folder, and a folder
  whose shortcut actually redirects (e.g. `firstChildNode`).

      lady-eleonode-rootford
      └─ site                   (Test.Routing.Page, name "node1", segment "site-ignored")
         └─ news                (Test.Routing.Page, segment "news")
            ├─ y2025            (Folder, hide=true, segment "2025")
            │  └─ m2025-09      (Folder, hide=true, segment "09")
            │     └─ post-hello (Test.Routing.Page, segment "hello")
            └─ y2026            (Folder, hide=true, segment "2026")

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

  Scenario: Creating a same-named hidden month folder under another hidden year is accepted
    # Relies on the NodeType defaults (hide=true, targetMode=noTarget) — the
    # Neos UI sends neither explicitly.
    When the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                                        |
      | nodeAggregateId           | "m2026-09"                                   |
      | parentNodeAggregateId     | "y2026"                                      |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder" |
      | originDimensionSpacePoint | {}                                           |
      | initialPropertyValues     | {"uriPathSegment": "09"}                     |
    And the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                         |
      | nodeAggregateId           | "post-fresh"                  |
      | parentNodeAggregateId     | "m2026-09"                    |
      | nodeTypeName              | "Neos.Neos:Test.Routing.Page" |
      | originDimensionSpacePoint | {}                            |
      | initialPropertyValues     | {"uriPathSegment": "fresh"}   |
    And I am on URL "/"
    Then the node "post-fresh" in dimension "{}" should resolve to URL "/news/fresh"
    And the node "post-hello" in dimension "{}" should resolve to URL "/news/hello"

  Scenario: A post whose URL matches a post in another hidden month folder is still rejected
    Given the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                                        |
      | nodeAggregateId           | "m2026-09"                                   |
      | parentNodeAggregateId     | "y2026"                                      |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder" |
      | originDimensionSpacePoint | {}                                           |
      | initialPropertyValues     | {"uriPathSegment": "09"}                     |
    When the command CreateNodeAggregateWithNode is executed with payload and exceptions are caught:
      | Key                       | Value                         |
      | nodeAggregateId           | "post-hello-2026"             |
      | parentNodeAggregateId     | "m2026-09"                    |
      | nodeTypeName              | "Neos.Neos:Test.Routing.Page" |
      | originDimensionSpacePoint | {}                            |
      | initialPropertyValues     | {"uriPathSegment": "hello"}   |
    Then the last command should have thrown an exception of type "UriPathCollisionDetected"

  Scenario: A page at the same URL as a hidden folder is still rejected
    # The router could resolve /news/09 to the folder (404) instead of the page.
    When the command CreateNodeAggregateWithNode is executed with payload and exceptions are caught:
      | Key                       | Value                         |
      | nodeAggregateId           | "page-09"                     |
      | parentNodeAggregateId     | "news"                        |
      | nodeTypeName              | "Neos.Neos:Test.Routing.Page" |
      | originDimensionSpacePoint | {}                            |
      | initialPropertyValues     | {"uriPathSegment": "09"}      |
    Then the last command should have thrown an exception of type "UriPathCollisionDetected"

  Scenario: A hidden folder that redirects is still rejected
    # /news/09 would redirect to whichever folder the router picks first.
    When the command CreateNodeAggregateWithNode is executed with payload and exceptions are caught:
      | Key                       | Value                                                |
      | nodeAggregateId           | "m2026-09"                                           |
      | parentNodeAggregateId     | "y2026"                                              |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder"         |
      | originDimensionSpacePoint | {}                                                   |
      | initialPropertyValues     | {"uriPathSegment": "09", "targetMode": "firstChildNode"} |
    Then the last command should have thrown an exception of type "UriPathCollisionDetected"

  Scenario: Hiding a year folder whose month folders share names with another year's is accepted
    # The original UI failure: toggling hideSegmentInUriPath on the year moves
    # its months from /news/2026/09 to /news/09, which m2025-09 already holds.
    Given the command SetNodeProperties is executed with payload:
      | Key                       | Value                             |
      | nodeAggregateId           | "y2026"                           |
      | originDimensionSpacePoint | {}                                |
      | propertyValues            | {"hideSegmentInUriPath": false}   |
    And the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                                        |
      | nodeAggregateId           | "m2026-09"                                   |
      | parentNodeAggregateId     | "y2026"                                      |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder" |
      | originDimensionSpacePoint | {}                                           |
      | initialPropertyValues     | {"uriPathSegment": "09"}                     |
    And the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                         |
      | nodeAggregateId           | "post-fresh"                  |
      | parentNodeAggregateId     | "m2026-09"                    |
      | nodeTypeName              | "Neos.Neos:Test.Routing.Page" |
      | originDimensionSpacePoint | {}                            |
      | initialPropertyValues     | {"uriPathSegment": "fresh"}   |
    When the command SetNodeProperties is executed with payload:
      | Key                       | Value                           |
      | nodeAggregateId           | "y2026"                         |
      | originDimensionSpacePoint | {}                              |
      | propertyValues            | {"hideSegmentInUriPath": true}  |
    And I am on URL "/"
    Then the node "post-fresh" in dimension "{}" should resolve to URL "/news/fresh"
    And the node "post-hello" in dimension "{}" should resolve to URL "/news/hello"

  Scenario: Moving a hidden month folder into another hidden year with a same-named month is accepted
    # Before the move the month lives at /news/drafts/09 (drafts is opaque);
    # afterwards at /news/09, which m2025-09 already holds.
    Given the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                                                     |
      | nodeAggregateId           | "drafts"                                                  |
      | parentNodeAggregateId     | "news"                                                    |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder"              |
      | originDimensionSpacePoint | {}                                                        |
      | initialPropertyValues     | {"uriPathSegment": "drafts", "hideSegmentInUriPath": false} |
    And the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                                        |
      | nodeAggregateId           | "m2026-09"                                   |
      | parentNodeAggregateId     | "drafts"                                     |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder" |
      | originDimensionSpacePoint | {}                                           |
      | initialPropertyValues     | {"uriPathSegment": "09"}                     |
    And the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                         |
      | nodeAggregateId           | "post-fresh"                  |
      | parentNodeAggregateId     | "m2026-09"                    |
      | nodeTypeName              | "Neos.Neos:Test.Routing.Page" |
      | originDimensionSpacePoint | {}                            |
      | initialPropertyValues     | {"uriPathSegment": "fresh"}   |
    When the command MoveNodeAggregate is executed with payload:
      | Key                                 | Value      |
      | nodeAggregateId                     | "m2026-09" |
      | dimensionSpacePoint                 | {}         |
      | newParentNodeAggregateId            | "y2026"    |
      | newSucceedingSiblingNodeAggregateId | null       |
    And I am on URL "/"
    Then the node "post-fresh" in dimension "{}" should resolve to URL "/news/fresh"

  Scenario: Renaming a hidden month folder to a name another hidden year already uses is accepted
    Given the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                                        |
      | nodeAggregateId           | "m2026-09"                                   |
      | parentNodeAggregateId     | "y2026"                                      |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder" |
      | originDimensionSpacePoint | {}                                           |
      | initialPropertyValues     | {"uriPathSegment": "10"}                     |
    When the command SetNodeProperties is executed with payload:
      | Key                       | Value                      |
      | nodeAggregateId           | "m2026-09"                 |
      | originDimensionSpacePoint | {}                         |
      | propertyValues            | {"uriPathSegment": "09"}   |
    And the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                         |
      | nodeAggregateId           | "post-fresh"                  |
      | parentNodeAggregateId     | "m2026-09"                    |
      | nodeTypeName              | "Neos.Neos:Test.Routing.Page" |
      | originDimensionSpacePoint | {}                            |
      | initialPropertyValues     | {"uriPathSegment": "fresh"}   |
    And I am on URL "/"
    Then the node "post-fresh" in dimension "{}" should resolve to URL "/news/fresh"

  Scenario: Letting a hidden folder redirect while another folder shares its URL is rejected
    # Would make /news/09 reachable, and ambiguous with m2025-09.
    Given the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                                        |
      | nodeAggregateId           | "m2026-09"                                   |
      | parentNodeAggregateId     | "y2026"                                      |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder" |
      | originDimensionSpacePoint | {}                                           |
      | initialPropertyValues     | {"uriPathSegment": "09"}                     |
    When the command SetNodeProperties is executed with payload and exceptions are caught:
      | Key                       | Value                              |
      | nodeAggregateId           | "m2026-09"                         |
      | originDimensionSpacePoint | {}                                 |
      | propertyValues            | {"targetMode": "firstChildNode"}   |
    Then the last command should have thrown an exception of type "UriPathCollisionDetected"

  Scenario: The Inspector's collision endpoint accepts renaming a hidden month folder to a shared name
    Given the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                                        |
      | nodeAggregateId           | "m2026-09"                                   |
      | parentNodeAggregateId     | "y2026"                                      |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder" |
      | originDimensionSpacePoint | {}                                           |
      | initialPropertyValues     | {"uriPathSegment": "10"}                     |
    When I POST JSON to URL "http://localhost/neos/folder/check-uri-collision":
    """
    {
      "workspaceName": "live",
      "nodeAggregateId": "m2026-09",
      "parentNodeAggregateId": "y2026",
      "dimensions": {},
      "propertyValues": {
        "uriPathSegment": "09"
      }
    }
    """
    Then the response status code should be 200

  Scenario: A second hidden month folder with the same segment under the same year is rejected
    # Siblings must keep unique segments, even when neither URL is reachable.
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

  Scenario: Moving a hidden month folder next to a same-named sibling is rejected
    Given the command CreateNodeAggregateWithNode is executed with payload:
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
      | newParentNodeAggregateId            | "y2025"    |
      | newSucceedingSiblingNodeAggregateId | null       |
    Then the last command should have thrown an exception of type "UriPathCollisionDetected"

  Scenario: Renaming a hidden month folder to a sibling's segment is rejected
    Given the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                                        |
      | nodeAggregateId           | "m2025-10"                                   |
      | parentNodeAggregateId     | "y2025"                                      |
      | nodeTypeName              | "Sandstorm.NodeTypes.Folder:Document.Folder" |
      | originDimensionSpacePoint | {}                                           |
      | initialPropertyValues     | {"uriPathSegment": "10"}                     |
    When the command SetNodeProperties is executed with payload and exceptions are caught:
      | Key                       | Value                    |
      | nodeAggregateId           | "m2025-10"               |
      | originDimensionSpacePoint | {}                       |
      | propertyValues            | {"uriPathSegment": "09"} |
    Then the last command should have thrown an exception of type "UriPathCollisionDetected"

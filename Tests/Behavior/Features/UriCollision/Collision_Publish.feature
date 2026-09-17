@flowEntities @contentrepository
Feature: Recreating a page whose earlier publish-then-removal was itself published

  All other UriCollision scenarios execute commands directly against the
  "live" workspace, so they never exercise an actual publish. The collision
  check queries the flat, workspace-agnostic `_uri` projection table directly
  (it has no workspaceName column -- see UriCollisionCheck), which only
  reflects events that have actually landed on live. Working purely in a
  draft workspace never touches that table at all, so a create/delete/
  recreate cycle done entirely without publishing never surfaces a
  collision -- that proves nothing about the real bug. The reported
  production bug only appears once a page has genuinely been published,
  then removed *and that removal published too*: re-creating the same
  uriPathSegment afterwards is rejected as colliding with the
  already-removed node.

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
      | nodeAggregateId | parentNodeAggregateId  | nodeTypeName                 | initialPropertyValues               | nodeName |
      | site-of-folders  | lady-eleonode-rootford | Neos.Neos:Test.Routing.Page  | {"uriPathSegment": "site-ignored"}  | node1    |
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

  Scenario: Recreating a segment succeeds once its earlier removal has actually been published
    Given I am in workspace "user-ws" and dimension space point {}
    And the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                          |
      | nodeAggregateId           | "page-1"                       |
      | parentNodeAggregateId     | "site-of-folders"              |
      | nodeTypeName              | "Neos.Neos:Test.Routing.Page"  |
      | originDimensionSpacePoint | {}                              |
      | initialPropertyValues     | {"uriPathSegment": "seite"}    |
    And the command PublishWorkspace is executed with payload:
      | Key                | Value              |
      | workspaceName      | "user-ws"          |
      | newContentStreamId | "cs-user-second"   |
    And I am on URL "/"
    Then the node "page-1" in dimension "{}" should resolve to URL "/seite"

    Given I am in workspace "user-ws" and dimension space point {}
    And the command RemoveNodeAggregate is executed with payload:
      | Key                          | Value          |
      | nodeAggregateId              | "page-1"       |
      | coveredDimensionSpacePoint   | {}             |
      | nodeVariantSelectionStrategy | "allVariants"  |
    And the command PublishWorkspace is executed with payload:
      | Key                | Value             |
      | workspaceName      | "user-ws"         |
      | newContentStreamId | "cs-user-third"   |

    Given I am in workspace "user-ws" and dimension space point {}
    When the command CreateNodeAggregateWithNode is executed with payload and exceptions are caught:
      | Key                       | Value                         |
      | nodeAggregateId           | "page-2"                      |
      | parentNodeAggregateId     | "site-of-folders"             |
      | nodeTypeName              | "Neos.Neos:Test.Routing.Page" |
      | originDimensionSpacePoint | {}                             |
      | initialPropertyValues     | {"uriPathSegment": "seite"}   |
    Then no exception of type "UriPathCollisionDetected" should be thrown
    And the command PublishWorkspace is executed with payload:
      | Key                | Value             |
      | workspaceName      | "user-ws"         |
      | newContentStreamId | "cs-user-fourth"  |
    And I am on URL "/"
    Then the node "page-2" in dimension "{}" should resolve to URL "/seite"

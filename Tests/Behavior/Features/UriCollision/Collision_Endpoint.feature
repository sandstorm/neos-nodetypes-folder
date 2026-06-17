@flowEntities @contentrepository
Feature: Editor-side validator endpoint surfaces collisions before the user saves

  The inspector POSTs the prospective state of a node to this endpoint before
  dispatching the actual command. A "200 ok" lets the inspector proceed; a
  "409 ok:false, conflicts:[]" blocks the Apply button with an inline error.

  The endpoint is a thin wrapper around the same UriCollisionCheck that
  Defense A uses — it's an early-warning system, not a second line of defense.

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

  Scenario: A non-colliding segment returns 200 ok
    When I POST JSON to URL "http://localhost/neos/folder/check-uri-collision":
    """
    {
      "workspaceName": "live",
      "parentNodeAggregateId": "folder-a",
      "dimensions": {},
      "propertyValues": {
        "uriPathSegment": "unique-segment"
      }
    }
    """
    Then the response status code should be 200
    And the response JSON should equal:
    """
    {"ok": true}
    """

  Scenario: A colliding new-child segment returns 409 with the conflict listed
    When I POST JSON to URL "http://localhost/neos/folder/check-uri-collision":
    """
    {
      "workspaceName": "live",
      "parentNodeAggregateId": "folder-a",
      "dimensions": {},
      "propertyValues": {
        "uriPathSegment": "sibling"
      }
    }
    """
    Then the response status code should be 409
    And the response JSON should contain key "ok" with value "false"
    And the first conflict in the response JSON should contain key "dimensionSpacePoint"
    And the first conflict in the response JSON should contain key "dimensionSpacePointHash"
    And the first conflict in the response JSON should contain key "uriPath"
    And the first conflict in the response JSON should contain key "otherNodeAggregateId"
    And the first conflict in the response JSON should contain key "otherNodeLabel"

  Scenario: A rename to a colliding segment returns 409
    When I POST JSON to URL "http://localhost/neos/folder/check-uri-collision":
    """
    {
      "workspaceName": "live",
      "nodeAggregateId": "child-in-folder",
      "parentNodeAggregateId": "folder-a",
      "dimensions": {},
      "propertyValues": {
        "uriPathSegment": "sibling"
      }
    }
    """
    Then the response status code should be 409

  Scenario: Re-setting the current segment (no-op rename) returns 200
    When I POST JSON to URL "http://localhost/neos/folder/check-uri-collision":
    """
    {
      "workspaceName": "live",
      "nodeAggregateId": "child-in-folder",
      "parentNodeAggregateId": "folder-a",
      "dimensions": {},
      "propertyValues": {
        "uriPathSegment": "child"
      }
    }
    """
    Then the response status code should be 200

  Scenario: A hide toggle that would create a descendant collision returns 409
    # Set up a colliding sibling first: rename folder-a to opaque so its
    # descendant "child" no longer collides, then add a new "/child" at the site
    # root. Toggling folder-a back to transparent would collide both at "/child".
    When the command SetNodeProperties is executed with payload:
      | Key                       | Value                              |
      | nodeAggregateId           | "folder-a"                         |
      | originDimensionSpacePoint | {}                                 |
      | propertyValues            | {"hideSegmentInUriPath": false}    |
    And the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                         |
      | nodeAggregateId           | "blocker"                     |
      | parentNodeAggregateId     | "site-of-folders"             |
      | nodeTypeName              | "Neos.Neos:Test.Routing.Page" |
      | originDimensionSpacePoint | {}                            |
      | initialPropertyValues     | {"uriPathSegment": "child"}   |
    And I POST JSON to URL "http://localhost/neos/folder/check-uri-collision":
    """
    {
      "workspaceName": "live",
      "nodeAggregateId": "folder-a",
      "dimensions": {},
      "propertyValues": {
        "hideSegmentInUriPath": true
      }
    }
    """
    Then the response status code should be 409

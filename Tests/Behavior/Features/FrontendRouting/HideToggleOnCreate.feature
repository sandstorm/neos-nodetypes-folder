@flowEntities @contentrepository
Feature: Folder created opaque, then toggled to transparent

  Covers the difference between the "insert path" (`hideUriSegmentForInsert`)
  and the "toggle path" (`applyHideToggle`). A folder created with
  `hideSegmentInUriPath: false` exposes its segment in descendant URLs from the
  start; a subsequent toggle to `true` must re-route descendants transparently.

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
      | nodeAggregateId | parentNodeAggregateId  | nodeTypeName                                  | initialPropertyValues                                              | nodeName |
      | site-of-folders | lady-eleonode-rootford | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "site-ignored"}                                 | node1    |
      | folder-opaque   | site-of-folders        | Sandstorm.NodeTypes.Folder:Document.Folder    | {"uriPathSegment": "folder-a", "hideSegmentInUriPath": false}      | folderA  |
      | child-in-folder | folder-opaque          | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "child"}                                        | child    |
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

  Scenario: Folder created with hide=false exposes its segment from the start
    When I am on URL "/"
    Then the node "child-in-folder" in dimension "{}" should resolve to URL "/folder-a/child"
    When I am on URL "/folder-a/child"
    Then the matched node should be "child-in-folder" in dimension "{}"
    When I am on URL "/child"
    Then No node should match URL "/child"

  Scenario: Toggling hide=false → true after create rewires the descendant
    When the command SetNodeProperties is executed with payload:
      | Key                       | Value                           |
      | nodeAggregateId           | "folder-opaque"                 |
      | originDimensionSpacePoint | {}                              |
      | propertyValues            | {"hideSegmentInUriPath": true}  |
    And I am on URL "/"
    Then the node "child-in-folder" in dimension "{}" should resolve to URL "/child"
    When I am on URL "/child"
    Then the matched node should be "child-in-folder" in dimension "{}"

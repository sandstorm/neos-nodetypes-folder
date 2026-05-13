@flowEntities @contentrepository
Feature: Route cache is flushed when `hideSegmentInUriPath` toggles

  Same shape as `Neos.Neos`' `RouteCache.feature`: warm the route cache by
  resolving every relevant URL once, mutate the folder's hide flag via
  `SetNodeProperties`, then assert the old URLs no longer match.
  Without `FolderRouterCacheHook` flushing tags for folder + descendants, the
  warm cache would still serve the pre-toggle answers and these assertions
  would fail.

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
      | nodeAggregateId | parentNodeAggregateId  | nodeTypeName                                  | initialPropertyValues                                        | nodeName |
      | site-of-folders | lady-eleonode-rootford | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "site-ignored"}                           | node1    |
      | folder-a        | site-of-folders        | Sandstorm.NodeTypes.Folder:Document.Folder    | {"uriPathSegment": "folder-a", "hideSegmentInUriPath": true} | folderA  |
      | child-in-folder | folder-a               | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "child"}                                  | child    |
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

  Scenario: Toggling hide=true → false flushes the cache; old transparent URL stops matching
    When I am on URL "/"
    And The URL "/child" should match the node "child-in-folder" in dimension "{}"
    And the command SetNodeProperties is executed with payload:
      | Key                       | Value                              |
      | nodeAggregateId           | "folder-a"                         |
      | originDimensionSpacePoint | {}                                 |
      | propertyValues            | {"hideSegmentInUriPath": false}    |
    Then No node should match URL "/child"
    And The URL "/folder-a/child" should match the node "child-in-folder" in dimension "{}"

  Scenario: Toggling hide=false → true flushes the cache; opaque URL stops matching
    When the command SetNodeProperties is executed with payload:
      | Key                       | Value                              |
      | nodeAggregateId           | "folder-a"                         |
      | originDimensionSpacePoint | {}                                 |
      | propertyValues            | {"hideSegmentInUriPath": false}    |
    And I am on URL "/"
    And The URL "/folder-a/child" should match the node "child-in-folder" in dimension "{}"
    And the command SetNodeProperties is executed with payload:
      | Key                       | Value                              |
      | nodeAggregateId           | "folder-a"                         |
      | originDimensionSpacePoint | {}                                 |
      | propertyValues            | {"hideSegmentInUriPath": true}     |
    Then No node should match URL "/folder-a/child"
    And The URL "/child" should match the node "child-in-folder" in dimension "{}"

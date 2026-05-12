@flowEntities @contentrepository
Feature: Nested folders, mixed transparent / opaque, and uriPathSegment renames

  Two-level nesting where a transparent folder contains both another transparent
  folder AND an opaque folder. The opaque folder must contribute its segment to
  descendant URLs; the transparent folders must not.

  Renames split into two branches in the projection (hunk 4 of
  `DocumentUriPathProjection`):
    - opaque folder rename → cascading core UPDATE; descendants flip.
    - transparent folder rename → folder-row-only UPDATE; descendants untouched.

  Tree B:

      lady-eleonode-rootford (Neos.Neos:Sites)
      └─ site-of-folders                       (Test.Routing.Page, name "node1", segment "site-ignored")
         ├─ folder-outer                       (Folder, hide=true,  segment "folder-outer")
         │  ├─ folder-inner-transparent        (Folder, hide=true,  segment "folder-inner-transparent")
         │  │  └─ deep-child                   (Test.Routing.Page, segment "deep")
         │  └─ folder-inner-opaque             (Folder, hide=false, segment "visible-folder")
         │     └─ deep-child-2                 (Test.Routing.Page, segment "deep")
         └─ regular-page                       (Test.Routing.Page, segment "regular")

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
      | nodeAggregateId            | parentNodeAggregateId      | nodeTypeName                                  | initialPropertyValues                                                          | nodeName |
      | site-of-folders            | lady-eleonode-rootford     | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "site-ignored"}                                             | node1    |
      | folder-outer               | site-of-folders            | Sandstorm.NodeTypes.Folder:Document.Folder    | {"uriPathSegment": "folder-outer", "hideSegmentInUriPath": true}               | outer    |
      | folder-inner-transparent   | folder-outer               | Sandstorm.NodeTypes.Folder:Document.Folder    | {"uriPathSegment": "folder-inner-transparent", "hideSegmentInUriPath": true}   | innerT   |
      | deep-child                 | folder-inner-transparent   | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "deep"}                                                     | deepC    |
      | folder-inner-opaque        | folder-outer               | Sandstorm.NodeTypes.Folder:Document.Folder    | {"uriPathSegment": "visible-folder", "hideSegmentInUriPath": false}            | innerO   |
      | deep-child-2               | folder-inner-opaque        | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "deep"}                                                     | deepC2   |
      | regular-page               | site-of-folders            | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "regular"}                                                  | regular  |
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

  Scenario: Walk skips ONLY transparent folders in both directions
    When I am on URL "/"
    Then the node "deep-child" in dimension "{}" should resolve to URL "/deep"
    And the node "deep-child-2" in dimension "{}" should resolve to URL "/visible-folder/deep"
    And the node "regular-page" in dimension "{}" should resolve to URL "/regular"
    When I am on URL "/deep"
    Then the matched node should be "deep-child" in dimension "{}"
    When I am on URL "/visible-folder/deep"
    Then the matched node should be "deep-child-2" in dimension "{}"

  Scenario: Renaming an OPAQUE folder cascades to descendants (core UPDATE branch)
    When the command SetNodeProperties is executed with payload:
      | Key                       | Value                       |
      | nodeAggregateId           | "folder-inner-opaque"       |
      | originDimensionSpacePoint | {}                          |
      | propertyValues            | {"uriPathSegment": "nu"}    |
    And I am on URL "/"
    Then the node "folder-inner-opaque" in dimension "{}" should resolve to URL "/nu"
    And the node "deep-child-2" in dimension "{}" should resolve to URL "/nu/deep"

  Scenario: Renaming a TRANSPARENT folder does not affect descendant URLs
    When the command SetNodeProperties is executed with payload:
      | Key                       | Value                               |
      | nodeAggregateId           | "folder-outer"                      |
      | originDimensionSpacePoint | {}                                  |
      | propertyValues            | {"uriPathSegment": "outer-renamed"} |
    And I am on URL "/"
    Then the node "deep-child" in dimension "{}" should resolve to URL "/deep"
    And the node "deep-child-2" in dimension "{}" should resolve to URL "/visible-folder/deep"
    And the node "regular-page" in dimension "{}" should resolve to URL "/regular"

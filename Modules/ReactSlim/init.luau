local ReactSlim = {}
local Shared = script.Parent

local React = require(Shared.React)
local ReactRoblox = require(Shared.ReactRoblox)
local ReactGlobals = require(Shared.ReactGlobals)

export type Binding<T> = React.Binding<T>
export type Object = React.Object 
export type ComponentType<P> = React.ComponentType<P>
export type ElementType = React.ElementType
export type Key = React.Key
export type Ref<T = any> = React.Ref<T>
export type RefObject<T = any> = React.RefObject<T>
export type Node = React.Node
export type Context<T> = React.Context<T>
export type ElementItem<C> = React.Element<C>
export type Element<Props = Object, Type = any> = React.ReactElement<Props, Type>
export type ReactElement<Props = Object, Type = any> = React.ReactElement<Props, Type>
export type Prop<T> = T | Binding<T>
export type FC<P> = React.FC<P>

export type RootType = {
    render: <Props, Type>(self: RootType, element: Element<Props, Type>) -> (),
    unmount: (self: RootType) -> ()
}

type Children<Props = any, Key = React.Key> = {
    [Key]: Element<Props>
}

type RootOptions = {
    hydrate: boolean?
}

ReactSlim.Globals = ReactGlobals

ReactSlim.createElement = React.createElement :: <Props, Type>(
    ty: Type,
    props: Props,
    ...any
) -> Element<Props, Type>

ReactSlim.cloneElement = React.cloneElement :: <Props, Type>(
    ty: Type,
    props: Props,
    ...any
) -> Element<Props, Type>

ReactSlim.isValidElement = React.isValidElement
    :: (element: any) -> boolean

ReactSlim.createRef = React.createRef
ReactSlim.forwardRef = React.forwardRef

ReactSlim.joinBindings = React.joinBindings
ReactSlim.createBinding = React.createBinding
ReactSlim.createContext = React.createContext
ReactSlim.createMutableSource = React.createMutableSource

ReactSlim.useEffect = React.useEffect ::
    & (<DepsArray>(effect: () -> (), deps: DepsArray?) -> ())
    & (<Cleanup, DepsArray>(effect: () -> Cleanup, deps: DepsArray?) -> ())

ReactSlim.useState = React.useState

ReactSlim.useMemo = React.useMemo :: 
    & (<DepsArray, T...>(factory: () -> T..., deps: DepsArray?) -> T...)

ReactSlim.useImperativeHandle = React.useImperativeHandle
ReactSlim.useMutableSource = React.useMutableSource
ReactSlim.useLayoutEffect = React.useLayoutEffect
ReactSlim.useCallback = React.useCallback
ReactSlim.useContext = React.useContext
ReactSlim.useReducer = React.useReducer
ReactSlim.useBinding = React.useBinding
ReactSlim.useRef = React.useRef

ReactSlim.memo = React.memo :: 
    <T>(element: T) -> T

ReactSlim.Tag = React.Tag
ReactSlim.None = React.None
ReactSlim.Fragment = React.Fragment :: Element
ReactSlim.Profiler = React.Profiler :: Element
ReactSlim.StrictMode = React.StrictMode :: Element

ReactSlim.Children = React.Children :: {
    map: <Props, K1, K2>(
        children: Children<Props, K1>, 
        fn: (child: Element<Props>) -> K2
    ) -> Children<Props, K2>,

    forEach: <Props, Key>(
        children: Children<Props, Key>, 
        fn: (child: Element<Props>) -> ()
    ) -> (),

    count: <Props, Key>(children: Children<Props, Key>) -> number,
    toArray: <Props, Key>(children: Children<Props, Key>) -> { Element<Props> },
    only: <Props, Key>(children: Children<Props, Key>) -> Element<Props>
}

ReactSlim.Event = React.Event :: Object
ReactSlim.Change = React.Change :: Object

ReactSlim.createRoot = ReactRoblox.createRoot :: (
    container: Instance, 
    options: RootOptions?
) -> RootType

ReactSlim.createLegacyRoot = ReactRoblox.createLegacyRoot :: (
    container: Instance, 
    options: RootOptions?
) -> RootType

ReactSlim.createBlockingRoot = ReactRoblox.createBlockingRoot :: (
    container: Instance, 
    options: RootOptions?
) -> RootType

ReactSlim.createPortal = ReactRoblox.createPortal :: <Props, Key>(
    children: Children<Props, Key>, 
    root: Instance
) -> Element

return table.freeze(ReactSlim)